"""Origin-root descriptors stay distinct from API-relative discovery paths."""

from dataclasses import replace

import pytest

from haveapi_client._protocol import (
    CallContext,
    build_request,
    lookup_action,
    parse_description,
    resolve_url,
)
from haveapi_client._transport import normalize_base_url
from haveapi_client.exceptions import ProtocolError

# Captured route forms from the real Ruby mounted fixture; not API-relative mocks.
ACTION = "/mount/v2/parents/{parent_id}/children/{widget_id}"
GLOBAL_TOKEN = "/mount/_auth/token/tokens"
VERSION_TOKEN = "/mount/v2/_auth/token/tokens"


def described_action(path):
    description = parse_description(
        {
            "version": "2.0",
            "status": True,
            "response": {
                "resources": {
                    "widget": {"actions": {"show": {"method": "GET", "path": path}}}
                }
            },
        }
    )
    return description, lookup_action(description, ("widget",), "show")


@pytest.mark.parametrize(
    "base",
    [
        "https://api.test",
        "https://api.test/",
        "https://api.test/mount",
        "https://api.test/mount/",
    ],
)
@pytest.mark.parametrize(
    "path", [ACTION, GLOBAL_TOKEN, VERSION_TOKEN, "/mount/v2/action_states/{state_id}"]
)
def test_descriptor_resolver_preserves_advertised_root_path(base, path):
    assert resolve_url(base, path, path_mode="descriptor") == "https://api.test" + path


@pytest.mark.parametrize("base", ["https://api.test/mount", "https://api.test/mount/"])
def test_base_validation_and_api_relative_resolution_keep_mount(base):
    assert normalize_base_url(base) == "https://api.test/mount/"
    assert resolve_url(base, "") == "https://api.test/mount/"
    assert resolve_url(base, "v2/") == "https://api.test/mount/v2/"
    assert resolve_url(base, "/v2/") == "https://api.test/mount/v2/"


@pytest.mark.parametrize(
    "identifier,encoded",
    [
        ("name with space", "name%20with%20space"),
        ("a/b", "a%2Fb"),
        ("a%2Fb", "a%252Fb"),
        ("a/../b", "a%2F..%2Fb"),
    ],
)
def test_binding_validates_static_route_before_encoding_id_data(identifier, encoded):
    description, action = described_action(ACTION)
    request = build_request(
        description,
        CallContext(action, (7, identifier), {}, 1),
        base_url="https://api.test/mount/",
    )
    assert request.url == "https://api.test/mount/v2/parents/7/children/" + encoded


@pytest.mark.parametrize(
    "path",
    [
        "v2/items",
        "",
        "//evil.test/mount/a",
        "https://evil.test/mount/a",
        "https://user:password@api.test/mount/a",
        "/mount/../secret",
        "/mount/%2e%2e/secret",
        "/mount/%252e%252e/secret",
        "/mount/a\\b",
        "/mount/%5cb",
        "/mount/a?token=value",
        "/mount/a#fragment",
        "/mount/\r\nvalue",
        "/mount/\x00value",
        "/%2fhost/mount/a",
    ],
)
def test_descriptor_invalid_forms_fail_before_binding(path):
    description, action = described_action(ACTION)
    # Malformed URLs can still be validated before any path values are consumed.
    action = replace(action, path=path)
    with pytest.raises(ProtocolError):
        build_request(
            description,
            CallContext(action, (), {}, 1),
            base_url="https://api.test/mount/",
        )
