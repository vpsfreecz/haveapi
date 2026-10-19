"""Asynchronous dynamic HaveAPI client."""

from __future__ import annotations

from collections.abc import Mapping
from typing import TYPE_CHECKING, Any, Self

import httpx

from haveapi_client._auth import (
    AsyncAuthenticationChallenge,
    Authenticated,
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
from haveapi_client._transport import AsyncTransport
from haveapi_client.exceptions import AuthenticationError

if TYPE_CHECKING:
    from haveapi_client.response import Response


class AsyncClient(ClientState):
    def __init__(
        self,
        base_url: str,
        *,
        version: str | None = None,
        auth: AuthProvider | None = None,
        timeout: float = 30.0,
        language: str | None = None,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        super().__init__(
            base_url, version=version, auth=auth, language=language, asynchronous=True
        )
        self._transport = AsyncTransport(timeout=timeout, http_client=http_client)

    async def _discover(
        self,
        description: Description | None = None,
        auth: AuthProvider | None = None,
    ) -> Description:
        wire = await self._transport.send(self._discovery_request(description, auth))
        return parse_description(decode_envelope(wire), api_version=self._version)

    async def _load(self) -> Description:
        public = await self._discover()
        return (
            await self._discover(public, self._auth)
            if self._auth is not None
            else public
        )

    async def connect(self) -> Self:
        with self._mutation():
            if self._description is None:
                self._install(await self._load())
        return self

    async def refresh_description(self) -> Description:
        with self._mutation():
            self._invalidate()
            description = await self._load()
            self._install(description)
            return description

    async def set_auth(self, auth: AuthProvider | None) -> Self:
        with self._mutation():
            self._invalidate()
            self._auth = auth
            self._install(await self._load())
        return self

    async def logout(self) -> None:
        await self.set_auth(None)

    async def _invoke(
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
            description,
            context.action,
            await self._transport.send(request, options=options),
        )

    async def execute(
        self,
        context: CallContext,
        *,
        params: InputParams | None = None,
        meta: Mapping[str, object] | None = None,
        options: RequestOptions | None = None,
    ) -> Response[Any]:
        from haveapi_client.response import adapt_async_response

        with self._request(context) as description:
            decoded = await self._invoke(
                description,
                context,
                auth=self._auth,
                params=params,
                meta=meta,
                options=options,
            )
            return adapt_async_response(decoded, context, self)

    async def begin_token_login(
        self, params: Mapping[str, object]
    ) -> Authenticated | AsyncAuthenticationChallenge:
        with self._mutation():
            self._invalidate()
            self._auth = None
            description = await self._discover()
            return await self._login_step(description, "request", params)

    async def _login_step(
        self,
        description: Description,
        name: str,
        params: Mapping[str, object],
    ) -> Authenticated | AsyncAuthenticationChallenge:
        action = self._token_action(description, name)
        context = CallContext(action, (), {}, self.generation)
        decoded = await self._invoke(description, context, auth=None, params=params)
        complete, token, valid_to, next_action = self._login_result(decoded.data)
        self._login = None
        if complete:
            auth = TokenAuth(token)
            authorized = await self._discover(description, auth)
            self._auth = auth
            self._install(authorized)
            return Authenticated(token, valid_to)
        assert next_action is not None
        fields, nonce = self._prepare_challenge(description, next_action)

        async def submit(
            values: Mapping[str, object],
        ) -> Authenticated | AsyncAuthenticationChallenge:
            with self._mutation():
                params = self._continuation_params(nonce, token, values)
                return await self._login_step(description, next_action, params)

        return AsyncAuthenticationChallenge(next_action, fields, valid_to, submit)

    async def renew_token(self) -> Response[Any]:
        with self._mutation():
            return await self._token_operation("renew")

    async def revoke_token(self) -> Response[Any]:
        with self._mutation():
            response = await self._token_operation("revoke")
            self._auth = None
            self._invalidate()
            self._install(await self._discover())
            return response

    async def _token_operation(self, name: str) -> Response[Any]:
        from haveapi_client.response import adapt_async_response

        if not isinstance(self._auth, TokenAuth):
            raise AuthenticationError("A connected token identity is required")
        description = self.description
        context = CallContext(
            self._token_action(description, name), (), {}, self.generation
        )
        return adapt_async_response(
            await self._invoke(description, context, auth=self._auth), context, self
        )

    async def aclose(self) -> None:
        if self._closed:
            return
        with self._mutation():
            self._invalidate()
            self._auth = None
            self._closed = True
            await self._transport.aclose()

    async def __aenter__(self) -> Self:
        try:
            return await self.connect()
        except BaseException:
            await self.aclose()
            raise

    async def __aexit__(self, *args: object) -> None:
        await self.aclose()
