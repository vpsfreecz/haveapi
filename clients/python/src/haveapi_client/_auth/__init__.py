"""Explicit authentication providers and resumable login outcomes."""

from __future__ import annotations

import base64
import re
from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import Protocol

from haveapi_client._protocol import Description, ParameterSpec
from haveapi_client.exceptions import AuthenticationError

_HEADER_NAME = re.compile(r"[!#$%&'*+.^_`|~0-9A-Za-z-]+\Z")
_FORBIDDEN = {
    "host",
    "content-length",
    "content-type",
    "transfer-encoding",
    "connection",
    "trailer",
    "te",
    "upgrade",
    "proxy-authorization",
    "proxy-connection",
    "accept",
    "accept-language",
    "user-agent",
    "cookie",
}


class AuthProvider(Protocol):
    @property
    def method(self) -> str: ...

    def headers(self, description: Description) -> Mapping[str, str]: ...


def validate_headers(headers: Mapping[str, str]) -> dict[str, str]:
    result: dict[str, str] = {}
    seen: set[str] = set()
    for name, value in headers.items():
        if (
            not isinstance(name, str)
            or not _HEADER_NAME.fullmatch(name)
            or name.lower() in _FORBIDDEN
            or name.lower() in seen
        ):
            raise AuthenticationError("Invalid authentication header name")
        if not isinstance(value, str) or any(
            ord(c) < 32 or ord(c) > 126 for c in value
        ):
            raise AuthenticationError("Invalid authentication header value")
        seen.add(name.lower())
        result[name] = value
    return result


@dataclass(frozen=True)
class BasicAuth:
    username: str = field(repr=False)
    password: str = field(repr=False)
    method = "basic"

    def headers(self, description: Description) -> Mapping[str, str]:
        if ":" in self.username or any(
            c in self.username + self.password for c in "\r\n"
        ):
            raise AuthenticationError("Invalid Basic credentials")
        encoded = base64.b64encode(f"{self.username}:{self.password}".encode()).decode(
            "ascii"
        )
        return {"Authorization": f"Basic {encoded}"}


@dataclass(frozen=True)
class TokenAuth:
    token: str = field(repr=False)
    method = "token"

    def headers(self, description: Description) -> Mapping[str, str]:
        provider = description.authentication.get(self.method)
        header = provider.get("http_header") if provider is not None else None
        if not isinstance(header, str):
            raise AuthenticationError("Token provider has no valid HTTP header")
        return validate_headers({header: self.token})


@dataclass(frozen=True)
class OAuth2Auth:
    access_token: str = field(repr=False)
    method = "oauth2"

    def headers(self, description: Description) -> Mapping[str, str]:
        return validate_headers({"Authorization": f"Bearer {self.access_token}"})


@dataclass(frozen=True)
class Authenticated:
    token: str = field(repr=False)
    valid_to: str | None = None


@dataclass(frozen=True)
class AuthenticationChallenge:
    next_action: str
    input: Mapping[str, ParameterSpec]
    valid_to: str | None
    _submit: Callable[
        [Mapping[str, object]], Authenticated | AuthenticationChallenge
    ] = field(repr=False, compare=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "input", MappingProxyType(dict(self.input)))

    def submit(
        self, params: Mapping[str, object]
    ) -> Authenticated | AuthenticationChallenge:
        return self._submit(params)


@dataclass(frozen=True)
class AsyncAuthenticationChallenge:
    next_action: str
    input: Mapping[str, ParameterSpec]
    valid_to: str | None
    _submit: Callable[
        [Mapping[str, object]], Awaitable[Authenticated | AsyncAuthenticationChallenge]
    ] = field(repr=False, compare=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "input", MappingProxyType(dict(self.input)))

    async def submit(
        self, params: Mapping[str, object]
    ) -> Authenticated | AsyncAuthenticationChallenge:
        return await self._submit(params)
