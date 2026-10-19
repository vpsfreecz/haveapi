"""Inspect real HTTPX wire bytes with Rack's parser, without a live server."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from urllib.parse import urlencode

import httpx
import pytest

from haveapi_client import AsyncClient, Client, ValidationError

pytestmark = [pytest.mark.integration, pytest.mark.anyio]


def layout(namespace: str | bool, fields: dict[str, str]) -> dict[str, object]:
    return {
        "layout": "hash",
        "namespace": namespace,
        "parameters": {name: {"type": kind} for name, kind in fields.items()},
    }


def description() -> dict[str, object]:
    actions = {}
    for name, method in (("get_rows", "GET"), ("delete_payload", "DELETE")):
        actions[name] = {
            "method": method,
            "path": f"/wire/{name}",
            "input": layout(
                "payload", {"rows": "Custom", "message": "String", "count": "Integer"}
            ),
            "output": layout(False, {}),
            "meta": {"global": {"input": layout("_meta", {"marker": "String"})}},
        }
    return {
        "version": "2.0",
        "status": True,
        "response": {"resources": {"wire": {"actions": actions, "resources": {}}}},
    }


def rack_parse(query: bytes) -> dict[str, object]:
    root = Path(__file__).resolve().parents[4]
    env = dict(os.environ, BUNDLE_GEMFILE=str(root / "servers/ruby/Gemfile"))
    env.pop("RUBYOPT", None)
    result = subprocess.run(
        [
            "bundle",
            "exec",
            "ruby",
            "-rjson",
            "-rrack/utils",
            "-rrack/version",
            "-e",
            "puts JSON.generate(rack_version: Rack.release, "
            "parsed: Rack::Utils.parse_nested_query(STDIN.read))",
        ],
        input=query,
        capture_output=True,
        cwd=root,
        env=env,
        check=False,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return json.loads(result.stdout)


async def call(
    mode: str,
    sent: list[httpx.Request],
    params: dict[str, object],
    action: str = "get_rows",
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "OPTIONS":
            return httpx.Response(200, json=description())
        sent.append(request)
        return httpx.Response(
            200, json={"version": "2.0", "status": True, "response": {}}
        )

    if mode == "sync":
        with httpx.Client(transport=httpx.MockTransport(handler)) as http:
            with Client("https://example.test", http_client=http) as api:
                api.wire.actions[action].call(params=params, meta={"marker": "m&=+"})
    else:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
            async with AsyncClient("https://example.test", http_client=http) as api:
                await api.wire.actions[action].call(
                    params=params, meta={"marker": "m&=+"}
                )


@pytest.mark.parametrize("mode", ["sync", "async"])
async def test_dense_custom_rows_survive_httpx_and_rack(mode: str) -> None:
    rows = [{"a": "one&=+", "b": "žluť /[]"}, {"b": "last", "a": "3"}]
    sent: list[httpx.Request] = []
    await call(mode, sent, {"rows": rows, "message": "雪&/[]=+?", "count": 2})
    assert len(sent) == 1
    actual = rack_parse(sent[0].url.query)
    assert actual["parsed"] == {
        "payload": {"rows": rows, "message": "雪&/[]=+?", "count": "2"},
        "_meta": {"marker": "m&=+"},
    }
    assert actual["rack_version"]
    assert sent[0].content == b""


@pytest.mark.parametrize("mode", ["sync", "async"])
@pytest.mark.parametrize(
    "rows",
    [
        [{"a": "1"}, {"b": "2"}],
        {},
        [],
        {"empty": []},
        [["one", "two"]],
        {"number": 2},
        {"boolean": False},
        {"null": None},
        {"literal[bracket]": "value"},
    ],
)
async def test_unrepresentable_custom_get_fails_before_action_io(
    mode: str, rows: object
) -> None:
    sent: list[httpx.Request] = []
    with pytest.raises(ValidationError):
        await call(mode, sent, {"rows": rows})
    assert sent == []


@pytest.mark.parametrize("mode", ["sync", "async"])
async def test_delete_uses_json_for_sparse_and_empty_values(mode: str) -> None:
    sent: list[httpx.Request] = []
    rows = [{"a": []}, {"b": {"empty": {}, "values": [False, 2, None]}}]
    await call(mode, sent, {"rows": rows}, "delete_payload")
    assert len(sent) == 1
    assert sent[0].method == "DELETE"
    assert sent[0].url.query == b""
    assert sent[0].headers["Content-Type"] == "application/json"
    assert json.loads(sent[0].content) == {
        "payload": {"rows": rows},
        "_meta": {"marker": "m&=+"},
    }


async def test_rack_sparse_rows_and_empty_array_are_not_lossless() -> None:
    sparse = urlencode([("payload[rows][][a]", "1"), ("payload[rows][][b]", "2")])
    assert rack_parse(sparse.encode())["parsed"] == {
        "payload": {"rows": [{"a": "1", "b": "2"}]}
    }
    assert rack_parse(b"payload%5Brows%5D%5B%5D=")["parsed"] == {
        "payload": {"rows": [""]}
    }
