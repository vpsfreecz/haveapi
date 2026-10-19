"""Shared pure connection state and concurrency gates for both client facades."""

from __future__ import annotations

import re
import threading
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from typing import Any

from haveapi_client._auth import AuthProvider, validate_headers
from haveapi_client._protocol import (
    ActionSpec,
    CallContext,
    Description,
    InputParams,
    ParameterSpec,
    RequestSpec,
    build_request,
    lookup_resource,
    parse_resources,
)
from haveapi_client._resources import Resource
from haveapi_client._transport import normalize_base_url, validate_destination
from haveapi_client.exceptions import (
    AuthenticationError,
    NotConnectedError,
    ProtocolError,
    StaleDescriptionError,
)


class ClientState:
    def __init__(
        self,
        base_url: str,
        *,
        version: str | None,
        auth: AuthProvider | None,
        language: str | None,
        asynchronous: bool,
    ) -> None:
        self._base_url = normalize_base_url(base_url)
        if version is not None and (
            not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]*", version)
        ):
            raise ValueError("Invalid API version")
        if language is not None and any(ord(c) < 32 or ord(c) > 126 for c in language):
            raise ValueError("Invalid language header")
        self._version = version
        self._auth = auth
        self._language = language
        self._description: Description | None = None
        self._generation = 0
        self._asynchronous = asynchronous
        self._lock = threading.RLock()
        self._active = 0
        self._mutating = False
        self._closed = False
        self._login: object | None = None

    def __repr__(self) -> str:
        return f"{type(self).__name__}(connected={self._description is not None})"

    @property
    def description(self) -> Description:
        if self._description is None:
            raise NotConnectedError("Call connect() before accessing API resources")
        return self._description

    @property
    def generation(self) -> int:
        return self._generation

    @property
    def resources(self) -> Mapping[str, Resource]:
        from types import MappingProxyType

        return MappingProxyType(
            {name: self.resource((name,)) for name in self.description.resources}
        )

    def resource(
        self,
        path: tuple[str, ...],
        *,
        bound_args: tuple[str | int, ...] = (),
        path_params: Mapping[str, str | int] | None = None,
    ) -> Resource:
        lookup_resource(self.description, path)
        return Resource(
            self,
            path,
            bound_args,
            path_params or {},
            self.generation,
            self._asynchronous,
        )

    def __getattr__(self, name: str) -> Any:
        if name.startswith("_"):
            raise AttributeError(name)
        if name in self.description.resources:
            return self.resource((name,))
        raise AttributeError(name)

    def __dir__(self) -> list[str]:
        return sorted(
            set(super().__dir__())
            | set(self._description.resources if self._description else ())
        )

    @contextmanager
    def _mutation(self) -> Iterator[None]:
        # Never hold a thread lock across network I/O or an await. The same
        # short reservation gate handles threads and independently scheduled tasks.
        with self._lock:
            if self._closed:
                raise NotConnectedError("Client is closed")
            if self._active or self._mutating:
                raise AuthenticationError(
                    "Client state is in use; retry the explicit state change later"
                )
            self._mutating = True
        try:
            yield
        finally:
            with self._lock:
                self._mutating = False

    @contextmanager
    def _request(self, context: CallContext) -> Iterator[Description]:
        with self._lock:
            if context.generation != self.generation:
                raise StaleDescriptionError("Action belongs to an old description")
            if self._mutating:
                raise AuthenticationError(
                    "Client authentication or description is changing"
                )
            description = self.description
            self._active += 1
        try:
            yield description
        finally:
            with self._lock:
                self._active -= 1

    def _invalidate(self) -> None:
        self._generation += 1
        self._description = None
        self._login = None

    def _install(self, description: Description) -> None:
        self._generation += 1
        self._description = description
        self._login = None

    def _headers(
        self, description: Description | None, auth: AuthProvider | None
    ) -> dict[str, str]:
        headers = {"Accept": "application/json", "User-Agent": "haveapi-client-python"}
        if self._language:
            headers["Accept-Language"] = self._language
        if auth is not None:
            if description is None or auth.method not in description.authentication:
                raise AuthenticationError("Authentication method is not advertised")
            headers.update(validate_headers(auth.headers(description)))
        return headers

    def _discovery_request(
        self,
        description: Description | None = None,
        auth: AuthProvider | None = None,
    ) -> RequestSpec:
        url = self._base_url + (
            f"v{self._version}/" if self._version is not None else ""
        )
        validate_destination(self._base_url, url)
        query = () if self._version is not None else (("describe", "default"),)
        return RequestSpec(
            "OPTIONS", url, query, self._headers(description, auth), None
        )

    def _action_request(
        self,
        description: Description,
        context: CallContext,
        *,
        auth: AuthProvider | None,
        params: InputParams | None = None,
        meta: Mapping[str, object] | None = None,
    ) -> RequestSpec:
        request = build_request(
            description, context, base_url=self._base_url, params=params, meta=meta
        )
        validate_destination(self._base_url, request.url)
        headers = dict(request.headers)
        headers.update(self._headers(description, auth))
        return RequestSpec(
            request.method, request.url, request.query, headers, request.content
        )

    def _token_action(self, description: Description, name: str) -> ActionSpec:
        provider = description.authentication.get("token")
        raw = provider.get("resources") if provider is not None else None
        if not isinstance(raw, Mapping):
            raise AuthenticationError("Token authentication is not advertised")
        resources = parse_resources(raw)
        token = resources.get("token")
        if token is None or name not in token.actions:
            raise AuthenticationError("Token authentication action is not advertised")
        return token.actions[name]

    def _login_result(self, data: object) -> tuple[bool, str, str | None, str | None]:
        if not isinstance(data, Mapping) or not isinstance(data.get("complete"), bool):
            raise ProtocolError("Invalid token authentication result")
        token = data.get("token")
        valid_to = data.get("valid_to")
        complete = data["complete"]
        next_action = data.get("next_action")
        if (
            not isinstance(token, str)
            or not token
            or (valid_to is not None and not isinstance(valid_to, str))
            or (not complete and (not isinstance(next_action, str) or not next_action))
        ):
            raise ProtocolError("Invalid token authentication result")
        return (
            complete,
            token,
            valid_to,
            next_action if isinstance(next_action, str) else None,
        )

    def _prepare_challenge(
        self,
        description: Description,
        next_action: str,
    ) -> tuple[Mapping[str, ParameterSpec], object]:
        """Validate a next step before installing its nonce under _mutation."""
        action = self._token_action(description, next_action)
        if action.input is None or "token" not in action.input.parameters:
            raise ProtocolError(
                "Authentication continuation must describe a token input"
            )
        fields = {
            key: value
            for key, value in action.input.parameters.items()
            if key != "token"
        }
        nonce = object()
        self._login = nonce
        return fields, nonce

    def _continuation_params(
        self,
        nonce: object,
        token: str,
        values: Mapping[str, object],
    ) -> Mapping[str, object]:
        """Check the current challenge and copy input without consuming retries."""
        if self._login is not nonce:
            raise AuthenticationError("Authentication challenge is no longer current")
        if "token" in values:
            raise AuthenticationError("Continuation token cannot be overridden")
        return {**values, "token": token}
