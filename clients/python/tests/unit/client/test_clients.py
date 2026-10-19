"""Both public facades exercise the same described wire behavior."""

from __future__ import annotations

import inspect
import json
from collections.abc import Callable
from dataclasses import FrozenInstanceError
from urllib.parse import parse_qsl

import httpx
import pytest

from haveapi_client._auth import (
    AsyncAuthenticationChallenge,
    Authenticated,
    AuthenticationChallenge,
    BasicAuth,
    OAuth2Auth,
    TokenAuth,
)
from haveapi_client._protocol import RequestOptions
from haveapi_client.async_client import AsyncClient
from haveapi_client.client import Client
from haveapi_client.exceptions import (
    ActionError,
    AuthenticationError,
    NotConnectedError,
    ProtocolError,
    StaleDescriptionError,
    TransportError,
)


def layout(namespace, fields, kind="hash"):
    return {
        "layout": kind,
        "namespace": namespace,
        "parameters": {
            name: {"type": typ, "required": False, "nullable": True}
            for name, typ in fields.items()
        },
    }


def action(path, *, method="GET", fields=None, output="hash", namespace="item"):
    return {
        "path": path,
        "method": method,
        "input": layout(namespace, fields or {}),
        "output": layout(namespace, {"id": "Integer"}, output),
    }


def description():
    index = action("/v7.0/items", fields={"limit": "Integer", "meta": "String"})
    index["aliases"] = ["list"]
    index["meta"] = {"global": {"input": layout("_meta", {"count": "Boolean"})}}
    token_output = layout(
        "token",
        {
            "token": "String",
            "complete": "Boolean",
            "next_action": "String",
            "valid_to": "Datetime",
        },
    )
    token_actions = {}
    for name, fields in {
        "request": {"user": "String", "password": "String"},
        "totp": {"token": "String", "code": "String"},
        "reset_password": {
            "token": "String",
            "new_password1": "String",
            "new_password2": "String",
        },
        "renew": {},
        "revoke": {},
    }.items():
        token_actions[name] = action(
            f"/v7.0/tokens/{name}", method="POST", fields=fields, namespace="token"
        )
        token_actions[name]["output"] = token_output
    return {
        "version": "2.0",
        "status": True,
        "response": {
            "resources": {
                "item": {
                    "actions": {
                        "index": index,
                        "show": action("/v7.0/items/{item_id}"),
                        "write": action(
                            "/v7.0/items",
                            method="POST",
                            fields={
                                "meta": "String",
                                "params": "String",
                                "class": "String",
                            },
                        ),
                        "batch": action("/v7.0/batch", method="POST"),
                    },
                    "resources": {
                        "child": {
                            "actions": {
                                "show": action(
                                    "/v7.0/items/{item_id}/children/{child_id}"
                                )
                            }
                        }
                    },
                },
                "close": {"actions": {"from": action("/v7.0/collisions")}},
            },
            "authentication": {
                "basic": {},
                "oauth2": {},
                "token": {
                    "http_header": "X-Test-Token",
                    "resources": {"token": {"actions": token_actions}},
                },
            },
            "meta": {"namespace": "_meta"},
        },
    }


def success(data=None, namespace="item"):
    return httpx.Response(
        200, json={"status": True, "response": {namespace: data or {"id": 1}}}
    )


class Server:
    def __init__(self):
        self.requests = []
        self.description = description()
        self.handler: Callable | None = None

    def __call__(self, request):
        self.requests.append(request)
        assert request.extensions["timeout"]["read"] > 0
        if self.handler is not None:
            result = self.handler(request)
            if result is not None:
                return result
        if request.method == "OPTIONS":
            return httpx.Response(200, json=self.description)
        return (
            success({"valid_to": None}, "token")
            if "/tokens/" in request.url.path
            else success()
        )


async def resolve(value):
    return await value if inspect.isawaitable(value) else value


@pytest.fixture(params=[False, True], ids=["sync", "async"])
def asynchronous(request):
    return request.param


@pytest.fixture
def anyio_backend():
    return "asyncio"


def make_client(server, asynchronous, **kwargs):
    cls = AsyncClient if asynchronous else Client
    http_cls = httpx.AsyncClient if asynchronous else httpx.Client
    injected = http_cls(
        transport=httpx.MockTransport(server),
        follow_redirects=True,
        headers={"X-Unwanted": "no"},
        cookies={"cookie": "no"},
        auth=("injected", "secret"),
    )
    return cls("https://api.example/mount/", http_client=injected, **kwargs), injected


async def close(client, injected, asynchronous):
    await resolve(client.aclose() if asynchronous else client.close())
    assert not injected.is_closed
    await resolve(injected.aclose() if asynchronous else injected.close())


@pytest.mark.anyio
async def test_navigation_wire_collisions_staleness(asynchronous):
    server = Server()
    client, injected = make_client(server, asynchronous, language="cs", timeout=12)
    assert server.requests == []
    with pytest.raises(NotConnectedError):
        _ = client.item
    await resolve(client.connect())
    before = len(server.requests)
    show = client.item["one/two"].child[2].show
    first = client.item[1].show
    assert "item" in dir(client)
    assert "show" in dir(client.item)
    assert len(server.requests) == before
    with pytest.raises(FrozenInstanceError):
        client.item._bound_args = (5,)
    await resolve(show())
    assert server.requests[-1].url.raw_path == b"/mount/v7.0/items/one%2Ftwo/children/2"
    await resolve(first())
    assert server.requests[-1].url.path == "/mount/v7.0/items/1"
    await resolve(
        client.item.list.call(
            params={"limit": 100},
            meta={"count": True},
            options=RequestOptions(timeout=3),
        )
    )
    assert server.requests[-1].url.params["item[limit]"] == "100"
    assert server.requests[-1].url.params["_meta[count]"] == "true"
    assert server.requests[-1].extensions["timeout"]["read"] == 3
    await resolve(client.item.write(meta="real", params="input"))
    assert json.loads(server.requests[-1].content) == {
        "item": {"meta": "real", "params": "input"}
    }
    await resolve(client.resources["close"].actions["from"].call())
    for request in server.requests:
        assert request.headers["accept-language"] == "cs"
        assert "authorization" not in request.headers
        assert "cookie" not in request.headers
        assert "x-unwanted" not in request.headers
    stale = client.item.show
    await resolve(client.refresh_description())
    count = len(server.requests)
    with pytest.raises(StaleDescriptionError):
        await resolve(stale.call(path_params={"item_id": 1}))
    assert len(server.requests) == count
    await close(client, injected, asynchronous)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "auth,expected",
    [
        (
            BasicAuth("alice", "password"),
            ("authorization", "Basic YWxpY2U6cGFzc3dvcmQ="),
        ),
        (TokenAuth("existing-secret"), ("x-test-token", "existing-secret")),
        (OAuth2Auth("bearer-secret"), ("authorization", "Bearer bearer-secret")),
    ],
)
async def test_connect_authorized_rediscovery_logout(asynchronous, auth, expected):
    server = Server()
    client, injected = make_client(server, asynchronous, auth=auth, version="7.0")
    await resolve(client.connect())
    assert len(server.requests) == 2
    name, value = expected
    assert name not in server.requests[0].headers
    assert server.requests[1].headers[name] == value
    assert server.requests[0].url.path == "/mount/v7.0/"
    await resolve(client.item[1].show())
    assert server.requests[-1].headers[name] == value
    old = client.item.show
    await resolve(client.logout())
    assert name not in server.requests[-1].headers
    with pytest.raises(StaleDescriptionError):
        await resolve(old.call(path_params={"item_id": 1}))
    assert "secret" not in repr(client)
    assert "secret" not in repr(auth)
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_resumable_totp_and_password_reset(asynchronous):
    server = Server()
    seen = []

    def handler(request):
        if request.method == "OPTIONS":
            return None
        if "/tokens/" not in request.url.path:
            return None
        step = request.url.path.rsplit("/", 1)[-1]
        values = json.loads(request.content)["token"]
        assert "x-test-token" not in request.headers
        seen.append((step, values))
        if step == "request":
            return success(
                {
                    "complete": False,
                    "token": "private-one",
                    "next_action": "totp",
                    "valid_to": None,
                },
                "token",
            )
        if step == "totp":
            assert values == {"token": "private-one", "code": "123456"}
            return success(
                {
                    "complete": False,
                    "token": "private-two",
                    "next_action": "reset_password",
                    "valid_to": None,
                },
                "token",
            )
        assert values == {
            "token": "private-two",
            "new_password1": "new",
            "new_password2": "new",
        }
        return success(
            {"complete": True, "token": "final-secret", "valid_to": None}, "token"
        )

    server.handler = handler
    client, injected = make_client(server, asynchronous)
    challenge = await resolve(
        client.begin_token_login({"user": "alice", "password": "old"})
    )
    kind = AsyncAuthenticationChallenge if asynchronous else AuthenticationChallenge
    assert isinstance(challenge, kind)
    assert challenge.next_action == "totp"
    assert set(challenge.input) == {"code"}
    assert "private-one" not in repr(challenge)
    assert "old" not in repr(client)
    with pytest.raises(NotConnectedError):
        _ = client.item
    with pytest.raises(AuthenticationError):
        await resolve(challenge.submit({"token": "override", "code": "123456"}))
    values = {"code": "123456"}
    next_challenge = await resolve(challenge.submit(values))
    assert values == {"code": "123456"}
    assert next_challenge.next_action == "reset_password"
    with pytest.raises(AuthenticationError):
        await resolve(challenge.submit({"code": "123456"}))
    result = await resolve(
        next_challenge.submit({"new_password1": "new", "new_password2": "new"})
    )
    assert isinstance(result, Authenticated)
    assert "final-secret" not in repr(result)
    assert server.requests[-1].method == "OPTIONS"
    assert server.requests[-1].headers["x-test-token"] == "final-secret"
    server.handler = None
    await resolve(client.item[1].show())
    assert server.requests[-1].headers["x-test-token"] == "final-secret"
    assert len(seen) == 3
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_explicit_renew_revoke_and_close_do_not_revoke(asynchronous):
    server = Server()
    client, injected = make_client(server, asynchronous, auth=TokenAuth("secret"))
    await resolve(client.connect())
    await resolve(client.renew_token())
    assert server.requests[-1].url.path.endswith("/tokens/renew")
    assert server.requests[-1].headers["x-test-token"] == "secret"
    await resolve(client.revoke_token())
    assert server.requests[-2].url.path.endswith("/tokens/revoke")
    assert server.requests[-2].headers["x-test-token"] == "secret"
    assert "x-test-token" not in server.requests[-1].headers
    before = len(server.requests)
    await close(client, injected, asynchronous)
    assert len(server.requests) == before


@pytest.mark.anyio
async def test_no_redirect_retry_or_external_credential_forwarding(asynchronous):
    server = Server()
    client, injected = make_client(server, asynchronous, auth=TokenAuth("secret"))
    await resolve(client.connect())
    server.handler = lambda request: httpx.Response(
        302, headers={"location": "https://evil.example/"}
    )
    before = len(server.requests)
    with pytest.raises((ActionError, ProtocolError)):
        await resolve(client.item[1].show())
    assert len(server.requests) == before + 1
    server.description["response"]["resources"]["item"]["actions"]["show"]["path"] = (
        "https://evil.example/{id}"
    )
    server.handler = None
    await resolve(client.refresh_description())
    before = len(server.requests)
    with pytest.raises(ProtocolError):
        await resolve(client.item[1].show())
    assert len(server.requests) == before
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_transport_error_is_redacted_and_not_retried(asynchronous):
    server = Server()
    client, injected = make_client(server, asynchronous)
    await resolve(client.connect())

    def handler(request):
        raise httpx.ReadTimeout("secret transport diagnostic", request=request)

    server.handler = handler
    before = len(server.requests)
    with pytest.raises(TransportError) as error:
        await resolve(client.item.write(meta="secret"))
    assert "secret" not in str(error.value)
    assert error.value.__cause__ is None
    assert len(server.requests) == before + 1
    await close(client, injected, asynchronous)


@pytest.mark.parametrize("timeout", [0, -1, float("inf"), float("nan"), True])
@pytest.mark.parametrize("cls", [Client, AsyncClient])
def test_finite_timeout(timeout, cls):
    with pytest.raises(ValueError):
        cls("https://api.example", timeout=timeout)


@pytest.mark.anyio
async def test_context_entry_connects_and_exit_closes_only_owned_transport(
    asynchronous,
):
    server = Server()
    client, injected = make_client(server, asynchronous)
    if asynchronous:
        async with client as connected:
            assert connected is client
            assert len(server.requests) == 1
    else:
        with client as connected:
            assert connected is client
            assert len(server.requests) == 1
    assert not injected.is_closed
    with pytest.raises(NotConnectedError):
        _ = client.item
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_state_mutation_rejected_during_active_request(asynchronous):
    server = Server()
    client, injected = make_client(server, asynchronous, auth=TokenAuth("stable"))
    await resolve(client.connect())
    generation = client.generation
    if asynchronous:

        async def handler(request):
            with pytest.raises(AuthenticationError):
                await client.logout()
            assert client.generation == generation
            assert request.headers["x-test-token"] == "stable"
            return success()

        injected._transport = httpx.MockTransport(handler)
    else:

        def handler(request):
            with pytest.raises(AuthenticationError):
                client.logout()
            assert client.generation == generation
            assert request.headers["x-test-token"] == "stable"
            return success()

        server.handler = handler
    await resolve(client.item[4].show())
    assert client.generation == generation
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_auth_header_injection_rejected_before_credential_request(asynchronous):
    for header in [
        "Host",
        "Content-Length",
        "X-Test\r\nInjected",
        "Bad Header",
        "Cookie",
    ]:
        server = Server()
        server.description["response"]["authentication"]["token"]["http_header"] = (
            header
        )
        client, injected = make_client(server, asynchronous, auth=TokenAuth("secret"))
        with pytest.raises(AuthenticationError):
            await resolve(client.connect())
        assert len(server.requests) == 1
        await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_list_layout_input_passes_to_shared_core(asynchronous):
    server = Server()
    server.description["response"]["resources"]["item"]["actions"]["batch"]["input"] = (
        layout("item", {"id": "Integer"}, "hash_list")
    )
    client, injected = make_client(server, asynchronous)
    await resolve(client.connect())
    await resolve(client.item.batch.call(params=[{"id": 1}, {"id": 2}]))
    assert json.loads(server.requests[-1].content) == {"item": [{"id": 1}, {"id": 2}]}
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_get_list_query_preserves_wire_row_order(asynchronous):
    server = Server()
    batch = server.description["response"]["resources"]["item"]["actions"]["batch"]
    batch["method"] = "GET"
    batch["path"] = "/v7.0/items/{item_id}/batch"
    batch["input"] = layout("item", {"a": "Integer", "b": "String"}, "hash_list")
    client, injected = make_client(server, asynchronous)
    await resolve(client.connect())
    special = "ž &%+/?"
    await resolve(
        client.item["one/two"].batch.call(
            params=[{"a": 1, "b": special}, {"a": 3, "b": "4"}],
        )
    )
    request = server.requests[-1]
    assert request.url.query == (
        b"item%5B%5D%5Ba%5D=1&item%5B%5D%5Bb%5D=%C5%BE+%26%25%2B%2F%3F"
        b"&item%5B%5D%5Ba%5D=3&item%5B%5D%5Bb%5D=4"
    )
    assert parse_qsl(request.url.query.decode("ascii")) == [
        ("item[][a]", "1"),
        ("item[][b]", special),
        ("item[][a]", "3"),
        ("item[][b]", "4"),
    ]
    assert request.url.raw_path.partition(b"?")[0] == (
        b"/mount/v7.0/items/one%2Ftwo/batch"
    )
    await close(client, injected, asynchronous)


@pytest.mark.anyio
@pytest.mark.parametrize("missing_input", [True, False], ids=["no-input", "no-token"])
async def test_continuation_requires_described_token_input(asynchronous, missing_input):
    server = Server()
    provider = server.description["response"]["authentication"]["token"]
    provider["resources"]["token"]["actions"]["totp"]["input"] = (
        None if missing_input else layout("token", {"code": "String"})
    )

    def handler(request):
        if request.method != "OPTIONS":
            return success(
                {
                    "complete": False,
                    "token": "private-continuation",
                    "next_action": "totp",
                    "valid_to": None,
                },
                "token",
            )
        return None

    server.handler = handler
    client, injected = make_client(server, asynchronous)
    with pytest.raises(ProtocolError, match="must describe a token input") as error:
        await resolve(client.begin_token_login({"user": "alice", "password": "old"}))
    assert "private-continuation" not in str(error.value)
    assert len(server.requests) == 2  # Public discovery and the initial login only.
    assert server.requests[-1].url.path.endswith("/tokens/request")
    with pytest.raises(NotConnectedError):
        _ = client.item
    await close(client, injected, asynchronous)


@pytest.mark.anyio
@pytest.mark.parametrize("invalidate", ["connect", "logout"])
async def test_challenge_invalidated_before_submit(asynchronous, invalidate):
    server = Server()

    def handler(request):
        if request.method != "OPTIONS":
            return success(
                {
                    "complete": False,
                    "token": "private-continuation",
                    "next_action": "totp",
                    "valid_to": None,
                },
                "token",
            )
        return None

    server.handler = handler
    client, injected = make_client(server, asynchronous)
    challenge = await resolve(
        client.begin_token_login({"user": "alice", "password": "old"})
    )
    await resolve(getattr(client, invalidate)())
    before = len(server.requests)
    with pytest.raises(AuthenticationError, match="no longer current"):
        await resolve(challenge.submit({"code": "123456"}))
    assert len(server.requests) == before
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_failed_auth_replacement_invalidates_old_proxies(asynchronous):
    server = Server()
    client, injected = make_client(server, asynchronous)
    await resolve(client.connect())
    old = client.item[1].show

    def handler(request):
        if request.headers.get("x-test-token") == "bad":
            return httpx.Response(
                401,
                json={"status": False, "message": "invalid credentials", "errors": {}},
            )
        return None

    server.handler = handler
    with pytest.raises(AuthenticationError):
        await resolve(client.set_auth(TokenAuth("bad")))
    before = len(server.requests)
    with pytest.raises(StaleDescriptionError):
        await resolve(old())
    assert len(server.requests) == before
    with pytest.raises(NotConnectedError):
        _ = client.item
    await close(client, injected, asynchronous)


@pytest.mark.anyio
async def test_async_calls_keep_independent_bindings_and_release_cancellation():
    import asyncio

    server = Server()
    client, injected = make_client(server, True)
    await client.connect()
    entered = asyncio.Event()
    release = asyncio.Event()
    paths = []

    async def handler(request):
        paths.append(request.url.path)
        entered.set()
        await release.wait()
        return success()

    injected._transport = httpx.MockTransport(handler)
    pending = asyncio.create_task(client.item[1].show())
    await entered.wait()
    second = asyncio.create_task(client.item[2].show())
    await asyncio.sleep(0)
    with pytest.raises(AuthenticationError):
        await client.refresh_description()
    pending.cancel()
    with pytest.raises(asyncio.CancelledError):
        await pending
    release.set()
    await second
    assert sorted(paths) == ["/mount/v7.0/items/1", "/mount/v7.0/items/2"]
    injected._transport = httpx.MockTransport(server)
    await client.refresh_description()
    await close(client, injected, True)


@pytest.mark.parametrize(
    "url",
    [
        "https://user:secret@example.test",
        "https://example.test/?secret=1",
        "https://example.test/#fragment",
        "https://example.test/%252e%252e/",
        "https://example.test/../",
        "https://example.test/\\evil",
        "https://example.test:0/",
        "https://example.test/\r\n",
        "file:///local",
    ],
)
@pytest.mark.parametrize("cls", [Client, AsyncClient])
def test_unsafe_base_url(url, cls):
    with pytest.raises(ValueError):
        cls(url)
