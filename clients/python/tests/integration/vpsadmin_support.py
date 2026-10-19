"""Private-manifest and TOTP helpers for the real vpsAdmin HTTP bridge."""

from __future__ import annotations

import base64
import hashlib
import hmac
import inspect
import json
import os
import stat
import struct
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import httpx
import pytest

from haveapi_client._protocol import (
    CallContext,
    Description,
    WireResponse,
    build_request,
    decode_response,
    lookup_action,
    parse_description,
    parse_resources,
)


def load_manifest() -> dict[str, Any]:
    filename = os.environ.get("HAVEAPI_VPSADMIN_MANIFEST")
    if filename is None:
        pytest.skip("Run through the guarded vpsAdmin RSpec bridge")
    path = Path(filename)
    info = path.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise RuntimeError("The vpsAdmin manifest must be private to the current user")
    manifest = json.loads(path.read_text())
    url = urlsplit(manifest["base_url"])
    if url.scheme != "http" or url.hostname != "127.0.0.1" or not url.port:
        raise RuntimeError("The vpsAdmin bridge must listen on loopback")
    return manifest


async def resolve(value: Any) -> Any:
    return await value if inspect.isawaitable(value) else value


def totp(secret: str) -> str:
    key = base64.b32decode(secret.upper() + "=" * (-len(secret) % 8))
    digest = hmac.digest(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1)
    offset = digest[-1] & 15
    code = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return f"{code % 1_000_000:06d}"


async def unused_totp(manifest: dict[str, Any]) -> str:
    """Wait for the next real TOTP interval; the server rejects replayed codes."""
    import anyio

    previous = manifest.get("last_totp_code")
    deadline = time.monotonic() + 35
    while True:
        code = totp(manifest["totp_secret"])
        if code != previous:
            return code
        if time.monotonic() >= deadline:
            raise RuntimeError("No fresh TOTP code within the next interval")
        await anyio.sleep(0.2)


async def assert_continuation_rejected(manifest: dict[str, Any]) -> None:
    """Prove over HTTP that a temporary login token is not an API identity."""
    base_url = manifest["base_url"]
    async with httpx.AsyncClient(timeout=10, trust_env=False) as http:
        public_wire = await http.options(base_url, params={"describe": "default"})
        public_wire.raise_for_status()
        public = parse_description(public_wire.json())
        provider = public.authentication["token"]
        resources = parse_resources(provider["resources"])
        request_action = resources["token"].actions["request"]
        spec = build_request(
            public,
            CallContext(request_action, (), {}, 0),
            base_url=base_url,
            params={
                "user": manifest["user"]["login"],
                "password": manifest["password"],
                "lifetime": "fixed",
                "interval": 3600,
                "scope": "all",
            },
        )
        response = await http.request(
            spec.method,
            spec.url,
            params=spec.query,
            headers=spec.headers,
            content=spec.content,
        )
        decoded = decode_response(
            public,
            request_action,
            WireResponse(
                response.status_code, dict(response.headers), response.content
            ),
        )
        result = decoded.data
        assert result["complete"] is False
        # Discover the protected action using the independent admin fixture;
        # no private challenge state or guessed endpoint path is used.
        admin = manifest["admin"]
        authorized_wire = await http.options(
            base_url,
            params={"describe": "default"},
            auth=httpx.BasicAuth(admin["login"], manifest["password"]),
        )
        authorized_wire.raise_for_status()
        authorized = parse_description(authorized_wire.json())
        current = lookup_action(authorized, ("user",), "current")
        protected = build_request(
            authorized,
            CallContext(current, (), {}, 0),
            base_url=base_url,
        )
        denied = await http.request(
            protected.method,
            protected.url,
            params=protected.query,
            headers={**protected.headers, provider["http_header"]: result["token"]},
            content=protected.content,
        )
        assert denied.status_code in (401, 403)
        assert denied.json()["status"] is False


async def assert_token_rejected(
    manifest: dict[str, Any],
    description: Description,
    token: str,
) -> None:
    """Check a fresh protected request; OPTIONS may return public discovery."""
    from haveapi_client import TokenAuth

    current = lookup_action(description, ("user",), "current")
    spec = build_request(
        description,
        CallContext(current, (), {}, 0),
        base_url=manifest["base_url"],
    )
    async with httpx.AsyncClient(timeout=10, trust_env=False) as http:
        denied = await http.request(
            spec.method,
            spec.url,
            params=spec.query,
            headers={**spec.headers, **TokenAuth(token).headers(description)},
            content=spec.content,
        )
    assert denied.status_code in (401, 403)
    assert denied.json()["status"] is False
