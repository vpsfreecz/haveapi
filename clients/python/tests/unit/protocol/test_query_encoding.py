"""GET's Rack subset and the server's JSON-body method split."""

import json

import httpx
import pytest

from haveapi_client import AsyncClient, Client
from haveapi_client._protocol import (
    CallContext,
    build_request,
    lookup_action,
    parse_description,
)
from haveapi_client.exceptions import ValidationError


def envelope(
    *,
    method="GET",
    layout="hash",
    namespace="payload",
    parameters=None,
    meta_parameters=None,
):
    return {
        "status": True,
        "version": "2.0",
        "response": {
            "meta": {"namespace": "control"},
            "resources": {
                "wire": {
                    "actions": {
                        "send": {
                            "method": method,
                            "path": "/mounted/v1/wire",
                            "input": {
                                "layout": layout,
                                "namespace": namespace,
                                "parameters": parameters
                                if parameters is not None
                                else {"value": {"type": "Custom"}},
                            },
                            "meta": {
                                "global": {
                                    "input": {
                                        "layout": "hash",
                                        "namespace": False,
                                        "parameters": meta_parameters
                                        if meta_parameters is not None
                                        else {"marker": {"type": "String"}},
                                    }
                                }
                            },
                        }
                    }
                }
            },
        },
    }


def request(params=None, *, meta=None, **description_options):
    description = parse_description(envelope(**description_options))
    action = lookup_action(description, ("wire",), "send")
    return build_request(
        description,
        CallContext(action, (), {}, 1),
        base_url="https://api.test/mounted/",
        params=params,
        meta=meta,
    )


def test_dense_custom_rows_canonicalize_keys_and_preserve_string_values():
    rows = [{"b": "ü&/[]", "a": "one"}, {"a": "three", "b": "four"}]
    result = request({"value": rows})
    assert result.query == (
        ("payload[value][][a]", "one"),
        ("payload[value][][b]", "ü&/[]"),
        ("payload[value][][a]", "three"),
        ("payload[value][][b]", "four"),
    )
    assert list(rows[0]) == ["b", "a"]


@pytest.mark.parametrize("layout", ["object_list", "hash_list"])
def test_dense_described_rows_restore_typed_fields(layout):
    result = request(
        [{"b": False, "a": "+1"}, {"a": 3, "b": True}],
        layout=layout,
        parameters={"a": {"type": "Integer"}, "b": {"type": "Boolean"}},
    )
    assert result.query == (
        ("payload[][a]", "1"),
        ("payload[][b]", "false"),
        ("payload[][a]", "3"),
        ("payload[][b]", "true"),
    )


@pytest.mark.parametrize(
    "value",
    [
        [],
        {},
        {"nested": []},
        {"nested": {}},
        [{"a": "1"}, {"b": "2"}],
        [{"a": "1"}, {}],
        [{}],
        [["a", "b"]],
        [{"a": ["nested"]}],
        [{"a": {"b": "nested"}}],
        ["scalar", {"a": "1"}],
        [{"a": "1"}, "scalar"],
        {"nested": 1},
        {"nested": False},
        {"nested": None},
        1,
        False,
        [{"a": 1}],
        {"": "empty key"},
        {"a[b]": "bracket key"},
    ],
)
def test_unrepresentable_custom_get_data_fails_with_field_path(value):
    with pytest.raises(ValidationError) as error:
        request({"value": value})
    assert error.value.errors
    assert all(path.startswith("payload[value]") for path in error.value.errors)


def test_scalar_string_arrays_and_typed_null_have_distinct_wire_values():
    result = request(
        {"values": ["b", "a&x", ""], "clear": None, "custom_null": None},
        parameters={
            "values": {"type": "Custom"},
            "clear": {"type": "Integer", "nullable": True},
            "custom_null": {"type": "Custom", "nullable": True},
        },
    )
    assert result.query == (
        ("payload[values][]", "b"),
        ("payload[values][]", "a&x"),
        ("payload[values][]", ""),
        ("payload[clear]", ""),
        ("payload[custom_null]", ""),
    )


@pytest.mark.parametrize("layout", ["hash", "object", "hash_list", "object_list"])
def test_omitted_get_input_and_empty_structural_meta_emit_no_pairs(layout):
    assert request(layout=layout, meta={}).query == ()


@pytest.mark.parametrize("layout", ["hash_list", "object_list"])
def test_explicit_empty_get_list_is_not_omission(layout):
    with pytest.raises(ValidationError):
        request([], layout=layout)
    with pytest.raises(ValidationError):
        request([{}], layout=layout)


@pytest.mark.parametrize(
    "options,params",
    [
        ({"namespace": "bad[name]"}, {"value": "text"}),
        ({"parameters": {"bad[name]": {"type": "String"}}}, {"bad[name]": "text"}),
        ({"parameters": {"": {"type": "String"}}}, {"": "text"}),
    ],
)
def test_ambiguous_query_key_components_fail_locally(options, params):
    with pytest.raises(ValidationError):
        request(params, **options)


def test_global_metadata_has_the_same_get_custom_boundary():
    with pytest.raises(ValidationError) as error:
        request(
            meta={"value": {"nested": False}},
            meta_parameters={"value": {"type": "Custom"}},
        )
    assert "control[value][nested]" in error.value.errors
    result = request(meta={"marker": "ü&[]"})
    assert result.query == (("control[marker]", "ü&[]"),)


@pytest.mark.parametrize("method", ["POST", "PUT", "DELETE"])
@pytest.mark.parametrize(
    "value", [[], {}, [{"a": 1}, {"b": False}], {"x": None, "empty": [], "object": {}}]
)
def test_json_methods_preserve_values_that_get_cannot_represent(method, value):
    result = request({"value": value}, method=method, meta={"marker": "kept"})
    assert result.method == method
    assert result.query == ()
    assert result.headers["Content-Type"] == "application/json"
    assert json.loads(result.content) == {
        "payload": {"value": value},
        "control": {"marker": "kept"},
    }


@pytest.mark.parametrize("method", ["POST", "PUT", "DELETE"])
def test_namespaced_json_list_preserves_empty_and_sparse_rows(method):
    for rows in ([], [{"a": 1}, {"b": 2}]):
        result = request(
            rows,
            method=method,
            layout="hash_list",
            parameters={"a": {"type": "Integer"}, "b": {"type": "Integer"}},
        )
        assert json.loads(result.content) == {"payload": rows}


@pytest.mark.parametrize("method", ["POST", "PUT", "DELETE"])
@pytest.mark.parametrize("rows", [[], [{"value": "one"}]])
def test_unnamespaced_json_list_root_is_rejected(method, rows):
    with pytest.raises(ValidationError, match="object root"):
        request(rows, method=method, layout="hash_list", namespace=False)


def test_json_exact_key_names_are_not_subject_to_query_key_restriction():
    result = request(
        {"bad[key]": {"": "kept"}},
        method="DELETE",
        namespace="ns[exact]",
        parameters={"bad[key]": {"type": "Custom"}},
    )
    assert json.loads(result.content) == {"ns[exact]": {"bad[key]": {"": "kept"}}}


def test_sync_rejects_unrepresentable_get_before_action_http_request():
    calls = []

    def handler(wire):
        calls.append(wire)
        assert wire.method == "OPTIONS"
        return httpx.Response(200, json=envelope())

    with httpx.Client(transport=httpx.MockTransport(handler)) as transport:
        with Client("https://api.test/mounted/", http_client=transport) as client:
            with pytest.raises(ValidationError):
                client.wire.send(value=[{"a": "one"}, {"b": "two"}])
    assert [call.method for call in calls] == ["OPTIONS"]


@pytest.mark.anyio
async def test_async_rejects_unrepresentable_get_before_action_http_request():
    calls = []

    def handler(wire):
        calls.append(wire)
        assert wire.method == "OPTIONS"
        return httpx.Response(200, json=envelope())

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as transport:
        async with AsyncClient(
            "https://api.test/mounted/", http_client=transport
        ) as client:
            with pytest.raises(ValidationError):
                await client.wire.send(value=[])
    assert [call.method for call in calls] == ["OPTIONS"]
