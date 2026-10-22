"""Wire fixtures follow the shared protocol and typed-input documents."""

import json
from datetime import UTC, date, datetime

import pytest

from haveapi_client._protocol import (
    CallContext,
    RequestOptions,
    WireResponse,
    build_request,
    coerce_input,
    decode_envelope,
    decode_response,
    lookup_action,
    parse_description,
    resolve_url,
)
from haveapi_client._protocol.description import parse_layout
from haveapi_client.exceptions import (
    ActionError,
    AuthenticationError,
    ProtocolError,
    ValidationError,
)


def description(
    *, layout="hash", namespace="entry", method="POST", parameters=None, mount=""
):
    return parse_description(
        {
            "version": "2.17",
            "status": True,
            "response": {
                "resources": {
                    "close": {
                        "actions": {
                            "from": {
                                "path": mount
                                + "/v7/parents/{parent_id}/entries/{entry_id}",
                                "method": method,
                                "aliases": ["class"],
                                "input": {
                                    "layout": layout,
                                    "namespace": namespace,
                                    "parameters": parameters or {},
                                },
                                "output": {
                                    "layout": layout,
                                    "namespace": namespace,
                                    "parameters": {},
                                },
                                "meta": {
                                    "global": {
                                        "input": {
                                            "layout": "hash",
                                            "namespace": False,
                                            "parameters": {
                                                "count": {"type": "Boolean"}
                                            },
                                        }
                                    }
                                },
                                "extension": {"future": [1, 2]},
                            }
                        }
                    }
                },
                "authentication": {},
                "meta": {"namespace": "control"},
            },
        }
    )


def context(desc, *, bound=("a/b ü?&", 5), named=None):
    return CallContext(lookup_action(desc, ("close",), "class"), bound, named or {}, 1)


def wire(payload, status=200):
    return WireResponse(
        status, {"Content-Type": "application/json"}, json.dumps(payload).encode()
    )


def test_exact_names_aliases_extensions_and_immutable_copies():
    desc = description()
    action = lookup_action(desc, ("close",), "from")
    assert lookup_action(desc, ("close",), "class") is action
    assert action.path_parameters == ("parent_id", "entry_id")
    assert action.raw["extension"]["future"] == (1, 2)
    with pytest.raises(TypeError):
        desc.resources["another"] = desc.resources["close"]
    assert desc.protocol_version == "2.17"
    assert desc.api_version is None


@pytest.mark.parametrize("version", [None, "1.9", "3.0", "2", "2.bad"])
def test_protocol_major_and_shape_fail_clearly(version):
    with pytest.raises(ProtocolError, match="protocol version"):
        parse_description(
            {"status": True, "version": version, "response": {"resources": {}}}
        )


@pytest.mark.parametrize(
    "entry",
    [
        {"method": "PATCH", "path": "/v1/value"},
        {"method": "GET", "path": "/v1/{unfinished"},
        {"method": "GET", "path": "/v1/value", "aliases": "list"},
        {
            "method": "GET",
            "path": "/v1/value",
            "output": {"layout": "unknown", "parameters": {}},
        },
    ],
)
def test_malformed_or_unsupported_action_description(entry):
    with pytest.raises(ProtocolError):
        parse_description(
            {
                "status": True,
                "version": "2.0",
                "response": {"resources": {"value": {"actions": {"act": entry}}}},
            }
        )


@pytest.mark.parametrize("payload", [{}, {"entry": []}, {"entry": "bad"}])
def test_missing_or_wrong_output_namespace_is_protocol_failure(payload):
    desc = description()
    with pytest.raises(ProtocolError) as error:
        decode_response(
            desc,
            context(desc).action,
            wire({"status": True, "response": payload}),
        )
    assert error.value.status_code == 200


def test_alias_ambiguity_and_canonical_precedence():
    desc = description()
    raw = json.loads(
        json.dumps({"status": True, "version": "2.0", "response": {"resources": {}}})
    )
    template = dict(desc.resources["close"].actions["from"].raw)
    # Independent simple actions keep the description fixture read-only.
    action = {"method": "GET", "path": "/v1/entries", "aliases": ["same"]}
    raw["response"]["resources"] = {
        "entry": {"actions": {"one": action, "two": action}}
    }
    parsed = parse_description(raw)
    with pytest.raises(KeyError, match="ambiguous"):
        lookup_action(parsed, ("entry",), "same")
    raw["response"]["resources"]["entry"]["actions"]["same"] = action
    assert lookup_action(parse_description(raw), ("entry",), "same").name == "same"
    assert template["method"] == "POST"


@pytest.mark.parametrize("layout", ["object", "hash", "object_list", "hash_list"])
def test_all_layouts_and_global_namespace(layout):
    desc = description(
        layout=layout, parameters={"class": {"type": "Integer"}}, mount="/mounted/api"
    )
    params = {"class": "+7"}
    value = [params] if layout.endswith("_list") else params
    request = build_request(
        desc,
        context(desc),
        base_url="https://api.test/mounted/api/",
        params=value,
        meta={"count": "yes"},
    )
    expected = [{"class": 7}] if layout.endswith("_list") else {"class": 7}
    assert json.loads(request.content) == {
        "entry": expected,
        "control": {"count": True},
    }
    assert (
        request.url
        == "https://api.test/mounted/api/v7/parents/a%2Fb%20%C3%BC%3F%26/entries/5"
    )
    decoded = decode_response(
        desc,
        context(desc).action,
        wire(
            {
                "status": True,
                "response": {"entry": expected, "control": {"total_count": 2}},
            }
        ),
    )
    assert decoded.data == expected
    assert decoded.meta["total_count"] == 2


def test_unwrapped_inputs_omission_null_defaults_and_no_mutation():
    desc = description(
        namespace=False,
        parameters={
            "clear": {"type": "Integer", "nullable": True},
            "defaulted": {"type": "Integer", "default": 9},
        },
    )
    params = {"clear": None}
    request = build_request(
        desc, context(desc), base_url="https://api.test", params=params
    )
    assert json.loads(request.content) == {"clear": None}
    assert params == {"clear": None}
    assert "None" not in repr(request)
    assert (
        json.loads(
            build_request(
                desc, context(desc), base_url="https://api.test", params={}
            ).content
        )
        == {}
    )


def test_query_nested_custom_values_repeated_arrays_and_null():
    desc = description(
        method="GET",
        mount="/base",
        parameters={
            "clear": {"type": "Integer", "nullable": True},
            "extra": {"type": "Custom"},
        },
    )
    request = build_request(
        desc,
        context(desc),
        base_url="https://api.test/base",
        params={"clear": None, "extra": {"filters": ["a&b", "c"], "ok": "true"}},
        meta={"count": False},
    )
    assert request.query == (
        ("entry[clear]", ""),
        ("entry[extra][filters][]", "a&b"),
        ("entry[extra][filters][]", "c"),
        ("entry[extra][ok]", "true"),
        ("control[count]", "false"),
    )
    assert request.content is None


@pytest.mark.parametrize(
    "path",
    [
        "https://other.test/a",
        "//other.test/a",
        "/../secret",
        "/%2e%2e/secret",
        "/%252e%252e/secret",
        "/a\\b",
        "/x?secret=y",
        "/x#z",
    ],
)
def test_endpoint_security(path):
    with pytest.raises(ProtocolError):
        resolve_url("https://api.test/mount", path)


@pytest.mark.parametrize(
    "bound,named",
    [
        ((True, 1), {}),
        ((1,), {}),
        ((1, 2, 3), {}),
        ((1, 2), {"wrong": 3}),
        ((1, 2), {"parent_id": 9}),
    ],
)
def test_invalid_bindings(bound, named):
    desc = description()
    with pytest.raises(ValidationError):
        build_request(
            desc, context(desc, bound=bound, named=named), base_url="https://api.test"
        )


@pytest.mark.parametrize(
    "kind,value,expected",
    [
        ("Integer", " +12 ", 12),
        ("Integer", 12.0, 12),
        ("Float", "1e3", 1000.0),
        ("Float", 2, 2.0),
        ("Boolean", " YES ", True),
        ("Boolean", 0, False),
        ("String", True, "true"),
        ("Text", 12, "12"),
        ("Resource", " 0042 ", 42),
        ("Datetime", "2020-01-31T10:20Z", "2020-01-31T10:20Z"),
        ("Datetime", date(2020, 1, 31), "2020-01-31"),
        ("Datetime", datetime(2020, 1, 31, tzinfo=UTC), "2020-01-31T00:00:00+00:00"),
    ],
)
def test_typed_inputs(kind, value, expected):
    layout = parse_layout({"layout": "hash", "parameters": {"value": {"type": kind}}})
    assert coerce_input(layout, {"value": value}) == {"value": expected}


@pytest.mark.parametrize(
    "kind,value",
    [
        ("Integer", True),
        ("Integer", "12.0"),
        ("Integer", 12.3),
        ("Integer", float("inf")),
        ("Float", False),
        ("Float", "NaN"),
        ("Float", float("nan")),
        ("Float", "12oops"),
        ("Boolean", 2),
        ("Boolean", 1.0),
        ("Boolean", "maybe"),
        ("String", []),
        ("Text", {}),
        ("Resource", -1),
        ("Resource", True),
        ("Resource", "x"),
        ("Datetime", "2020-02-30"),
        ("Datetime", "2020-01-01T10:20"),
        ("Datetime", "2020-01-01T10:20+01:99"),
        ("Datetime", datetime(2020, 1, 1)),
        ("Custom", {"x": float("inf")}),
    ],
)
def test_invalid_typed_values(kind, value):
    layout = parse_layout({"layout": "hash", "parameters": {"value": {"type": kind}}})
    with pytest.raises(ValidationError) as error:
        coerce_input(layout, {"value": value})
    assert "value" in error.value.errors


def test_required_nullable_and_list_errors():
    layout = parse_layout(
        {
            "layout": "object_list",
            "parameters": {"id": {"type": "Integer", "required": True}},
        }
    )
    with pytest.raises(ValidationError) as error:
        coerce_input(layout, [{"id": 1}, {"id": False}, {}])
    assert set(error.value.errors) == {"1", "2"}
    assert coerce_input(layout, []) == []
    with pytest.raises(ValidationError):
        coerce_input(layout, {})


@pytest.mark.parametrize("status", [200, 400, 403, 404, 500])
def test_action_error_envelope_with_http_context(status):
    with pytest.raises(ActionError) as error:
        decode_envelope(
            wire(
                {
                    "status": False,
                    "response": {"private_field": "secret"},
                    "message": "localized message",
                    "errors": {"name": ["invalid"]},
                },
                status,
            )
        )
    assert error.value.status_code == status
    assert error.value.message == "localized message"
    assert error.value.errors["name"] == ["invalid"]
    assert error.value.envelope["response"] == "<redacted>"


def test_http_failure_is_not_hidden_by_success_envelope():
    with pytest.raises(AuthenticationError):
        decode_envelope(wire({"status": True, "response": {}}, 401))
    with pytest.raises(ActionError):
        decode_envelope(wire({"status": True, "response": {}}, 503))


@pytest.mark.parametrize(
    "body",
    [
        b"<html>bad gateway</html>",
        b"[]",
        b'{"status": 1}',
        b'{"status": true}',
        b'{"status": true, "response": NaN}',
    ],
)
def test_malformed_response_preserves_http_context(body):
    with pytest.raises(ProtocolError) as error:
        decode_envelope(WireResponse(502, {}, body))
    assert error.value.status_code == 502


@pytest.mark.parametrize("timeout", [0, -1, float("inf"), float("nan"), True])
def test_finite_request_timeouts(timeout):
    with pytest.raises(ValueError):
        RequestOptions(timeout)
