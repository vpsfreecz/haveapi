"""Synchronous dynamic HaveAPI client."""

from __future__ import annotations

from collections.abc import Mapping
from typing import TYPE_CHECKING, Any, Self

import httpx

from haveapi_client._auth import (
    Authenticated,
    AuthenticationChallenge,
    AuthProvider,
    TokenAuth,
)
from haveapi_client._protocol import (
    CallContext,
    DecodedResponse,
    Description,
    InputParams,
    RequestOptions,
    decode_envelope,
    decode_response,
    parse_description,
)
from haveapi_client._resources.state import ClientState
from haveapi_client._transport import SyncTransport
from haveapi_client.exceptions import AuthenticationError

if TYPE_CHECKING:
    from haveapi_client.response import Response


class Client(ClientState):
    def __init__(
        self,
        base_url: str,
        *,
        version: str | None = None,
        auth: AuthProvider | None = None,
        timeout: float = 30.0,
        language: str | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        super().__init__(
            base_url, version=version, auth=auth, language=language, asynchronous=False
        )
        self._transport = SyncTransport(timeout=timeout, http_client=http_client)

    def _discover(
        self,
        description: Description | None = None,
        auth: AuthProvider | None = None,
    ) -> Description:
        wire = self._transport.send(self._discovery_request(description, auth))
        return parse_description(decode_envelope(wire), api_version=self._version)

    def _load(self) -> Description:
        public = self._discover()
        return self._discover(public, self._auth) if self._auth is not None else public

    def connect(self) -> Self:
        with self._mutation():
            if self._description is None:
                self._install(self._load())
        return self

    def refresh_description(self) -> Description:
        with self._mutation():
            self._invalidate()
            description = self._load()
            self._install(description)
            return description

    def set_auth(self, auth: AuthProvider | None) -> Self:
        with self._mutation():
            self._invalidate()
            self._auth = auth
            self._install(self._load())
        return self

    def logout(self) -> None:
        self.set_auth(None)

    def _invoke(
        self,
        description: Description,
        context: CallContext,
        *,
        auth: AuthProvider | None,
        params: InputParams | None = None,
        meta: Mapping[str, object] | None = None,
        options: RequestOptions | None = None,
    ) -> DecodedResponse:
        request = self._action_request(
            description, context, auth=auth, params=params, meta=meta
        )
        return decode_response(
            description, context.action, self._transport.send(request, options=options)
        )

    def execute(
        self,
        context: CallContext,
        *,
        params: InputParams | None = None,
        meta: Mapping[str, object] | None = None,
        options: RequestOptions | None = None,
    ) -> Response[Any]:
        from haveapi_client.response import adapt_response

        with self._request(context) as description:
            decoded = self._invoke(
                description,
                context,
                auth=self._auth,
                params=params,
                meta=meta,
                options=options,
            )
            return adapt_response(decoded, context, self)

    def begin_token_login(
        self, params: Mapping[str, object]
    ) -> Authenticated | AuthenticationChallenge:
        with self._mutation():
            self._invalidate()
            self._auth = None
            description = self._discover()
            return self._login_step(description, "request", params)

    def _login_step(
        self,
        description: Description,
        name: str,
        params: Mapping[str, object],
    ) -> Authenticated | AuthenticationChallenge:
        action = self._token_action(description, name)
        context = CallContext(action, (), {}, self.generation)
        decoded = self._invoke(description, context, auth=None, params=params)
        complete, token, valid_to, next_action = self._login_result(decoded.data)
        self._login = None
        if complete:
            auth = TokenAuth(token)
            authorized = self._discover(description, auth)
            self._auth = auth
            self._install(authorized)
            return Authenticated(token, valid_to)
        assert next_action is not None
        fields, nonce = self._prepare_challenge(description, next_action)

        def submit(
            values: Mapping[str, object],
        ) -> Authenticated | AuthenticationChallenge:
            with self._mutation():
                params = self._continuation_params(nonce, token, values)
                return self._login_step(description, next_action, params)

        return AuthenticationChallenge(next_action, fields, valid_to, submit)

    def renew_token(self) -> Response[Any]:
        with self._mutation():
            return self._token_operation("renew")

    def revoke_token(self) -> Response[Any]:
        with self._mutation():
            response = self._token_operation("revoke")
            self._auth = None
            self._invalidate()
            self._install(self._discover())
            return response

    def _token_operation(self, name: str) -> Response[Any]:
        from haveapi_client.response import adapt_response

        if not isinstance(self._auth, TokenAuth):
            raise AuthenticationError("A connected token identity is required")
        description = self.description
        context = CallContext(
            self._token_action(description, name), (), {}, self.generation
        )
        return adapt_response(
            self._invoke(description, context, auth=self._auth), context, self
        )

    def close(self) -> None:
        if self._closed:
            return
        with self._mutation():
            self._invalidate()
            self._auth = None
            self._closed = True
            self._transport.close()

    def __enter__(self) -> Self:
        try:
            return self.connect()
        except BaseException:
            self.close()
            raise

    def __exit__(self, *args: object) -> None:
        self.close()
