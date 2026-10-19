import pytest

from haveapi_client._protocol import (
    CallContext,
    DecodedResponse,
    build_request,
    lookup_action,
    parse_description,
)
from haveapi_client.exceptions import StaleDescriptionError, ValidationError
from haveapi_client.operations import AsyncOperation, Operation
from haveapi_client.response import (
    Association,
    AsyncAssociation,
    ResourceObject,
    Response,
    adapt_async_response,
    adapt_response,
)


def action(path, *, layout="object", parameters=None, blocking=False):
    return {
        "path": path,
        "method": "GET",
        "blocking": blocking,
        "output": {
            "layout": layout,
            "namespace": "value",
            "parameters": parameters or {},
        },
    }


def make_description():
    association = {
        "type": "Resource",
        "resource": ["parent", "child"],
        "value_id": "key",
        "value_label": "title",
    }
    return parse_description(
        {
            "status": True,
            "version": "2.0",
            "response": {
                "meta": {"namespace": "control"},
                "resources": {
                    "parent": {
                        "resources": {
                            "child": {
                                "actions": {
                                    "index": action(
                                        "/v1/parents/{parent_id}/children",
                                        layout="object_list",
                                        parameters={"peer": association},
                                    ),
                                    "show": action(
                                        "/v1/parents/{parent_id}/children/{child_id}"
                                    ),
                                }
                            }
                        }
                    },
                    "task": {"actions": {"run": action("/v1/tasks", blocking=True)}},
                },
            },
        }
    )


class Executor:
    def __init__(self):
        self.description = make_description()
        self.generation = 4
        self.calls = []
        self.resources = []

    def resource(self, path, *, bound_args=(), path_params=None):
        binding = (path, bound_args, path_params)
        self.resources.append(binding)
        return binding

    def execute(self, context, **kwargs):
        self.calls.append((context, kwargs))
        return Response({"loaded": True}, {}, 200, {}, {})


class AsyncExecutor(Executor):
    async def execute(self, context, **kwargs):
        return super().execute(context, **kwargs)


def test_finite_objects_collisions_and_parent_binding_without_io():
    executor = Executor()
    spec = lookup_action(executor.description, ("parent", "child"), "index")
    context = CallContext(spec, (7,), {}, 4)
    decoded = DecodedResponse(
        [{"id": 9, "items": "field", "password": "private"}],
        {"total_count": 1},
        {},
        200,
        {},
    )
    result = adapt_response(decoded, context, executor)
    obj = result.data[0]
    assert isinstance(obj, ResourceObject)
    assert obj.id == 9
    assert obj["items"] == "field"
    assert callable(obj.items)
    assert "private" not in repr(obj)
    assert "private" not in repr(result)
    assert obj.resource == (("parent", "child"), (), {"parent_id": 7, "child_id": 9})
    assert not executor.calls
    with pytest.raises(TypeError):
        obj["id"] = 10
    executor.generation = 5
    with pytest.raises(StaleDescriptionError):
        _ = obj.resource


@pytest.mark.parametrize("asynchronous", [False, True])
def test_association_prefetch_fields_and_exact_metadata_binding(asynchronous):
    executor = AsyncExecutor() if asynchronous else Executor()
    spec = lookup_action(executor.description, ("parent", "child"), "index")
    decoded = DecodedResponse(
        [
            {
                "id": 9,
                "peer": {
                    "key": 12,
                    "title": "A peer",
                    "extra": "prefetched",
                    "control": {"path_params": [8, 12]},
                },
            }
        ],
        {},
        {},
        200,
        {},
    )
    adapter = adapt_async_response if asynchronous else adapt_response
    obj = adapter(decoded, CallContext(spec, (7,), {}, 4), executor).data[0]
    assert obj.peer.id == 12
    assert obj.peer.label == "A peer"
    assert obj.peer.extra == "prefetched"
    assert obj.peer.resource == (
        ("parent", "child"),
        (),
        {"parent_id": 8, "child_id": 12},
    )
    assert not executor.calls
    assert isinstance(obj.peer, AsyncAssociation if asynchronous else Association)


def test_association_fetch_is_explicit_and_missing_parent_never_guessed():
    executor = Executor()
    spec = lookup_action(executor.description, ("parent", "child"), "index")
    context = CallContext(spec, (7,), {}, 4)
    result = adapt_response(
        DecodedResponse(
            [{"id": 9, "peer": {"key": 12, "title": "peer"}}], {}, {}, 200, {}
        ),
        context,
        executor,
    )
    with pytest.raises(ValidationError, match="identity is incomplete"):
        result.data[0].peer.fetch()
    assert not executor.calls
    complete = adapt_response(
        DecodedResponse(
            [{"peer": {"key": 12, "control": {"path_params": [8, 12]}}}],
            {},
            {},
            200,
            {},
        ),
        context,
        executor,
    )
    assert complete.data[0].peer.fetch().data == {"loaded": True}
    assert executor.calls[0][0].path_params == {"parent_id": 8, "child_id": 12}


@pytest.mark.anyio
async def test_async_association_fetch_returns_async_action_response():
    executor = AsyncExecutor()
    spec = lookup_action(executor.description, ("parent", "child"), "index")
    decoded = DecodedResponse(
        [{"peer": {"key": 12, "control": {"path_params": [8, 12]}}}], {}, {}, 200, {}
    )
    response = adapt_async_response(decoded, CallContext(spec, (7,), {}, 4), executor)
    assert (await response.data[0].peer.fetch()).data == {"loaded": True}


def test_single_object_metadata_uses_actual_server_global_location():
    executor = Executor()
    spec = lookup_action(executor.description, ("parent", "child"), "show")
    metadata = {"path_params": [8, 12], "etag": "one"}
    response = adapt_response(
        DecodedResponse({"id": 12}, metadata, {}, 200, {}),
        CallContext(spec, (8, 12), {}, 4),
        executor,
    )
    assert response.data.meta["etag"] == "one"
    assert response.meta["path_params"] == (8, 12)
    assert response.data.resource[2] == {"parent_id": 8, "child_id": 12}


def test_object_id_never_fills_missing_parent_identifier():
    executor = Executor()
    spec = lookup_action(executor.description, ("parent", "child"), "show")
    response = adapt_response(
        DecodedResponse({"id": 12}, {}, {}, 200, {}),
        CallContext(spec, (), {"child_id": 12}, 4),
        executor,
    )
    assert response.data.resource[2] == {"child_id": 12}
    assert not executor.calls


class CustomActionExecutor(Executor):
    def __init__(self):
        super().__init__()
        self.description = parse_description(
            {
                "status": True,
                "version": "2.0",
                "response": {
                    "resources": {
                        "job": {
                            "actions": {
                                "run": action(
                                    "/v1/jobs/{job_id}/run",
                                    parameters={
                                        "peer": {
                                            "type": "Resource",
                                            "resource": ["job"],
                                            "value_id": "id",
                                            "value_label": "name",
                                        }
                                    },
                                )
                            }
                        }
                    }
                },
            }
        )

    def resource(self, path, *, bound_args=(), path_params=None):
        from haveapi_client._resources import Resource

        return Resource(self, path, bound_args, path_params or {}, self.generation)

    def execute(self, context, **kwargs):
        build_request(self.description, context, base_url="https://api.test")
        return super().execute(context, **kwargs)


@pytest.mark.parametrize("bound,named", [((7,), {}), ((), {"job_id": 7})])
@pytest.mark.parametrize("asynchronous", [False, True])
def test_no_show_ordinary_object_retains_originating_bindings(
    bound, named, asynchronous
):
    executor = CustomActionExecutor()
    spec = lookup_action(executor.description, ("job",), "run")
    adapter = adapt_async_response if asynchronous else adapt_response
    response = adapter(
        DecodedResponse({"id": 7}, {}, {}, 200, {}),
        CallContext(spec, bound, named, 4),
        executor,
    )
    assert not executor.calls
    response.data.resource.run()
    assert executor.calls[0][0].bound_args == bound
    assert executor.calls[0][0].path_params == named


def test_no_show_fallback_does_not_infer_identity_or_copy_association_context():
    executor = CustomActionExecutor()
    spec = lookup_action(executor.description, ("job",), "run")
    response = adapt_response(
        DecodedResponse({"id": 7}, {}, {}, 200, {}),
        CallContext(spec, (), {}, 4),
        executor,
    )
    with pytest.raises(ValidationError, match="missing path"):
        response.data.resource.run()
    response = adapt_response(
        DecodedResponse({"id": 7, "peer": {"id": 9}}, {}, {}, 200, {}),
        CallContext(spec, (7,), {}, 4),
        executor,
    )
    with pytest.raises(ValidationError, match="missing path"):
        response.data.peer.resource.run()
    assert not executor.calls


@pytest.mark.parametrize(
    "layout,value", [("hash", {"id": 1}), ("hash_list", [{"id": 1}])]
)
def test_hash_layouts_stay_ordinary_data(layout, value):
    executor = Executor()
    raw = {
        "status": True,
        "version": "2.0",
        "response": {
            "resources": {
                "value": {"actions": {"index": action("/v1/value", layout=layout)}}
            }
        },
    }
    executor.description = parse_description(raw)
    spec = lookup_action(executor.description, ("value",), "index")
    result = adapt_response(
        DecodedResponse(value, {}, {}, 200, {}), CallContext(spec, (), {}, 4), executor
    )
    assert type(result.data) is type(value)
    assert not isinstance(result.data, ResourceObject)


@pytest.mark.parametrize("asynchronous", [False, True])
def test_blocking_response_keeps_data_and_creates_monitor_only(asynchronous):
    executor = AsyncExecutor() if asynchronous else Executor()
    spec = lookup_action(executor.description, ("task",), "run")
    adapter = adapt_async_response if asynchronous else adapt_response
    response = adapter(
        DecodedResponse({"id": 9}, {"action_state_id": 27}, {}, 200, {}),
        CallContext(spec, (), {}, 4),
        executor,
    )
    assert response.data.id == 9
    assert response.meta["action_state_id"] == 27
    assert isinstance(response.operation, AsyncOperation if asynchronous else Operation)
    assert response.operation.action_state_id == 27
    assert not executor.calls
