"""Bind the real mounted Ruby OPTIONS description without starting a listener."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

from haveapi_client._protocol import (
    CallContext,
    build_request,
    lookup_action,
    parse_description,
    parse_resources,
)

pytestmark = pytest.mark.integration


@pytest.fixture(scope="module")
def mounted_description():
    root = Path(__file__).resolve().parents[4]
    environment = dict(os.environ, BUNDLE_GEMFILE=str(root / "servers/ruby/Gemfile"))
    environment.pop("RUBYOPT", None)
    result = subprocess.run(
        [
            "bundle",
            "exec",
            "ruby",
            "-rrack/mock",
            "-r./servers/ruby/test_support/dynamic_documentation_api",
            "-e",
            "request = Rack::MockRequest.new(DynamicDocumentationAPI.build.app); "
            "reply = request.request('OPTIONS', 'http://example.test/mount/v2/', "
            "'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT' => 'application/json', "
            "'HTTP_AUTHORIZATION' => 'Basic ' + "
            "['fixture-user:fixture-password'].pack('m0')); "
            "abort('mounted OPTIONS failed') unless reply.status == 200; "
            "puts reply.body",
        ],
        cwd=root,
        env=environment,
        capture_output=True,
        check=False,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return parse_description(json.loads(result.stdout))


def test_ordinary_action_preserves_real_ruby_mounted_descriptor(mounted_description):
    action = lookup_action(mounted_description, ("constructor", "resources"), "new")
    assert action.path == "/mount/v2/parents/{parent_id}/children/{widget_id}"
    request = build_request(
        mounted_description,
        CallContext(action, (7, "name with space"), {}, 1),
        base_url="http://example.test/mount/",
    )
    assert (
        request.url
        == "http://example.test/mount/v2/parents/7/children/name%20with%20space"
    )


def test_authentication_preserves_real_global_token_routes(mounted_description):
    resources = parse_resources(
        mounted_description.authentication["token"]["resources"]
    )
    token = resources["token"]
    assert token.actions["request"].path == "/mount/_auth/token/tokens"
    assert token.actions["verify"].path == "/mount/_auth/token/tokens/verify"
    for name, params in [
        (
            "request",
            {
                "user": "fixture-user",
                "password": "fixture-password",
                "lifetime": "renewable_auto",
            },
        ),
        ("verify", {"token": "fixture-challenge", "code": "123456"}),
    ]:
        action = token.actions[name]
        request = build_request(
            mounted_description,
            CallContext(action, (), {}, 1),
            base_url="http://example.test/mount/",
            params=params,
        )
        assert request.url == "http://example.test" + action.path
