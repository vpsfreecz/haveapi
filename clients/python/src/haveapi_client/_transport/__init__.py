"""HTTPX adapters. Requests never inherit injected-client auth or cookies."""

from __future__ import annotations

import math
from urllib.parse import unquote, urlencode, urlsplit

import httpx

from haveapi_client._protocol import (
    RequestOptions,
    RequestSpec,
    WireResponse,
    resolve_url,
)
from haveapi_client.exceptions import ProtocolError, TransportError


def finite_timeout(value: float) -> float:
    if isinstance(value, bool) or not math.isfinite(value) or value <= 0:
        raise ValueError("timeout must be positive and finite")
    return value


def normalize_base_url(value: str) -> str:
    if any(ord(c) < 32 or ord(c) == 127 for c in value) or "\\" in value:
        raise ValueError("base_url contains unsafe characters")
    url = urlsplit(value)
    if (
        url.scheme not in {"https", "http"}
        or not url.hostname
        or url.username is not None
        or url.password is not None
        or url.query
        or url.fragment
    ):
        raise ValueError(
            "base_url must be an HTTP(S) URL without credentials, query or fragment"
        )
    try:
        if url.port is not None and not 0 < url.port <= 65535:
            raise ValueError("Invalid port")
    except ValueError as exc:
        raise ValueError("base_url has an invalid port") from exc
    if any(segment in {".", ".."} for segment in unquote(url.path).split("/")):
        raise ValueError("base_url must not contain path traversal")
    try:
        resolve_url(value, "")
    except ProtocolError:
        raise ValueError("base_url contains an unsafe path") from None
    return value.rstrip("/") + "/"


def validate_destination(base_url: str, destination: str) -> None:
    base = urlsplit(base_url)
    url = urlsplit(destination)
    try:
        same_origin = (
            url.scheme.lower(),
            url.hostname,
            url.port or (443 if url.scheme == "https" else 80),
        ) == (
            base.scheme.lower(),
            base.hostname,
            base.port or (443 if base.scheme == "https" else 80),
        )
    except ValueError as exc:
        raise ProtocolError("Invalid destination URL") from exc
    if (
        not same_origin
        or url.username is not None
        or url.password is not None
        or url.fragment
        or not url.path.startswith(base.path)
    ):
        raise ProtocolError("Request destination is outside the configured API")


def _request(
    spec: RequestSpec, timeout: float, options: RequestOptions | None
) -> httpx.Request:
    effective = (
        timeout if options is None or options.timeout is None else options.timeout
    )
    finite_timeout(effective)
    # HTTPX params groups duplicate names, which changes Rack's row boundaries
    # for arrays of objects. Preserve the protocol core's complete pair order.
    query = urlencode(spec.query).encode("ascii")
    url = httpx.URL(spec.url).copy_with(query=query or None)
    return httpx.Request(
        spec.method,
        url,
        headers=spec.headers,
        content=spec.content,
        extensions={"timeout": httpx.Timeout(effective).as_dict()},
    )


class SyncTransport:
    def __init__(
        self, *, timeout: float, http_client: httpx.Client | None = None
    ) -> None:
        self.timeout = finite_timeout(timeout)
        self.owned = http_client is None
        self.client = (
            http_client if http_client is not None else httpx.Client(timeout=timeout)
        )

    def send(
        self, spec: RequestSpec, *, options: RequestOptions | None = None
    ) -> WireResponse:
        try:
            response = self.client.send(
                _request(spec, self.timeout, options), auth=None, follow_redirects=False
            )
        except httpx.HTTPError:
            # HTTPX exception messages can include request URLs and credentials.
            raise TransportError("HTTP request failed") from None
        return WireResponse(
            response.status_code, dict(response.headers), response.content
        )

    def close(self) -> None:
        if self.owned:
            self.client.close()


class AsyncTransport:
    def __init__(
        self, *, timeout: float, http_client: httpx.AsyncClient | None = None
    ) -> None:
        self.timeout = finite_timeout(timeout)
        self.owned = http_client is None
        self.client = (
            http_client
            if http_client is not None
            else httpx.AsyncClient(timeout=timeout)
        )

    async def send(
        self, spec: RequestSpec, *, options: RequestOptions | None = None
    ) -> WireResponse:
        try:
            response = await self.client.send(
                _request(spec, self.timeout, options), auth=None, follow_redirects=False
            )
        except httpx.HTTPError:
            raise TransportError("HTTP request failed") from None
        return WireResponse(
            response.status_code, dict(response.headers), response.content
        )

    async def aclose(self) -> None:
        if self.owned:
            await self.client.aclose()
