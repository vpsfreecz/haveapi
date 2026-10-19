import anyio
import pytest

from haveapi_client import operations
from haveapi_client._protocol import lookup_action, parse_description
from haveapi_client.exceptions import (
    ActionError,
    OperationFailedError,
    OperationTimeoutError,
    ProtocolError,
    StaleDescriptionError,
    TransportError,
)
from haveapi_client.operations import AsyncOperation, Operation
from haveapi_client.response import Response


class Executor:
    def __init__(self, states):
        self.generation = 3
        self.description = parse_description(
            {
                "status": True,
                "version": "2.0",
                "response": {
                    "resources": {
                        "action_state": {
                            "actions": {
                                name: {
                                    "path": f"/v1/action_states/{{state_id}}/{name}",
                                    "method": "GET" if name == "show" else "POST",
                                }
                                for name in ("show", "cancel")
                            }
                        }
                    }
                },
            }
        )
        self.states = iter(states)
        self.calls = []

    def resource(self, *args, **kwargs):
        raise AssertionError("monitor executes its described action directly")

    def execute(self, context, **kwargs):
        self.calls.append((context, kwargs))
        value = next(self.states)
        if isinstance(value, Exception):
            raise value
        return Response(value, {}, 200, {}, {})


class AsyncExecutor(Executor):
    async def execute(self, context, **kwargs):
        return super().execute(context, **kwargs)


class Clock:
    def __init__(self):
        self.now = 0.0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds

    async def asleep(self, seconds):
        self.sleep(seconds)


@pytest.fixture
def fake_clock(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(operations.time, "monotonic", clock.monotonic)
    monkeypatch.setattr(operations.time, "sleep", clock.sleep)
    monkeypatch.setattr(operations.anyio, "sleep", clock.asleep)
    return clock


def test_success_wait_returns_terminal_response_and_bounds_request_timeout(fake_clock):
    executor = Executor(
        [
            {"finished": False, "status": None},
            {"finished": True, "status": True, "current": 10},
        ]
    )
    operation = Operation(executor, 3, 19)
    terminal = operation.wait(timeout=10, interval=2)
    assert terminal.data["current"] == 10
    assert [kwargs["options"].timeout for _, kwargs in executor.calls] == [10, 8]
    assert all(context.bound_args == (19,) for context, _ in executor.calls)
    assert all(context.action.name == "show" for context, _ in executor.calls)


def test_unfinished_timeout_retains_operation_id_and_never_cancels(fake_clock):
    executor = Executor([{"finished": False}, {"finished": False}])
    operation = Operation(executor, 3, 19)
    with pytest.raises(OperationTimeoutError) as error:
        operation.wait(timeout=2, interval=1)
    assert error.value.operation_id == 19
    assert [context.action.name for context, _ in executor.calls] == ["show", "show"]


def test_terminal_failure_is_not_transport_or_timeout(fake_clock):
    executor = Executor([{"finished": True, "status": False}])
    with pytest.raises(OperationFailedError) as error:
        Operation(executor, 3, 19).wait()
    assert error.value.operation_id == 19
    assert error.value.status_code == 200


def test_http_poll_failure_propagates_without_replay(fake_clock):
    failure = ActionError("poll forbidden", status_code=403)
    executor = Executor([failure])
    with pytest.raises(ActionError) as error:
        Operation(executor, 3, 19).wait()
    assert error.value is failure
    assert len(executor.calls) == 1


@pytest.mark.parametrize("expired", [False, True])
def test_transport_failure_classification_uses_wait_deadline(expired, fake_clock):
    failure = TransportError("request timed out")

    class TimedExecutor(Executor):
        def execute(self, context, **kwargs):
            self.calls.append((context, kwargs))
            fake_clock.now = 2 if expired else 0.5
            raise failure

    executor = TimedExecutor([])
    expected = OperationTimeoutError if expired else TransportError
    with pytest.raises(expected) as error:
        Operation(executor, 3, 19).wait(timeout=1)
    if expired:
        assert error.value.__cause__ is failure
        assert error.value.operation_id == 19
    else:
        assert error.value is failure
    assert [context.action.name for context, _ in executor.calls] == ["show"]


@pytest.mark.anyio
@pytest.mark.parametrize("expired", [False, True])
async def test_async_transport_failure_uses_deadline(expired, fake_clock):
    failure = TransportError("request timed out")

    class TimedExecutor(AsyncExecutor):
        async def execute(self, context, **kwargs):
            self.calls.append((context, kwargs))
            fake_clock.now += 2 if expired else 0.5
            raise failure

    executor = TimedExecutor([])
    expected = OperationTimeoutError if expired else TransportError
    with pytest.raises(expected) as error:
        await AsyncOperation(executor, 3, 19).wait(timeout=1)
    assert error.value.__cause__ is failure if expired else error.value is failure
    assert [context.action.name for context, _ in executor.calls] == ["show"]


@pytest.mark.anyio
async def test_async_own_deadline_bounds_inflight_request():
    class SlowExecutor(AsyncExecutor):
        async def execute(self, context, **kwargs):
            self.calls.append((context, kwargs))
            await anyio.sleep_forever()

    executor = SlowExecutor([])
    with pytest.raises(OperationTimeoutError) as error:
        await AsyncOperation(executor, 3, 19).wait(timeout=0.01)
    assert error.value.operation_id == 19
    assert isinstance(error.value.__cause__, TimeoutError)
    assert [context.action.name for context, _ in executor.calls] == ["show"]


@pytest.mark.anyio
async def test_async_foreign_timeout_is_preserved():
    failure = TimeoutError("application timeout")
    executor = AsyncExecutor([failure])
    with pytest.raises(TimeoutError) as error:
        await AsyncOperation(executor, 3, 19).wait()
    assert error.value is failure
    assert [context.action.name for context, _ in executor.calls] == ["show"]


@pytest.mark.parametrize(
    "state", [{"finished": "yes"}, {"finished": True, "status": None}]
)
def test_malformed_state_is_protocol_error(state, fake_clock):
    executor = Executor([state])
    with pytest.raises(ProtocolError):
        Operation(executor, 3, 19).wait()


def test_cancel_requires_advertised_action_and_current_capability():
    executor = Executor([{"can_cancel": False}])
    with pytest.raises(OperationFailedError, match="cannot be cancelled"):
        Operation(executor, 3, 19).cancel()
    assert [context.action.name for context, _ in executor.calls] == ["show"]
    executor = Executor([{"can_cancel": True}, {"cancelled": True}])
    assert Operation(executor, 3, 19).cancel().data == {"cancelled": True}
    assert [context.action.name for context, _ in executor.calls] == ["show", "cancel"]


def test_stale_generation_prevents_all_network():
    executor = Executor([])
    operation = Operation(executor, 2, 19)
    with pytest.raises(StaleDescriptionError):
        operation.show()
    assert not executor.calls


@pytest.mark.anyio
async def test_async_success_failure_timeout_and_cancel(fake_clock):
    executor = AsyncExecutor([{"finished": False}, {"finished": True, "status": True}])
    assert (await AsyncOperation(executor, 3, 19).wait(timeout=5)).data["finished"]
    executor = AsyncExecutor([{"finished": True, "status": False}])
    with pytest.raises(OperationFailedError):
        await AsyncOperation(executor, 3, 19).wait()
    executor = AsyncExecutor([{"finished": False}])
    with pytest.raises(OperationTimeoutError):
        await AsyncOperation(executor, 3, 19).wait(timeout=1, interval=1)
    executor = AsyncExecutor([{"can_cancel": True}, {"cancelled": True}])
    assert (await AsyncOperation(executor, 3, 19).cancel()).data["cancelled"]


@pytest.mark.anyio
async def test_coroutine_cancellation_never_requests_remote_cancel():
    class SlowExecutor(AsyncExecutor):
        async def execute(self, context, **kwargs):
            self.calls.append((context, kwargs))
            await anyio.sleep_forever()

    executor = SlowExecutor([])
    with anyio.move_on_after(0.01) as scope:
        await AsyncOperation(executor, 3, 19).wait()
    assert scope.cancel_called
    assert [context.action.name for context, _ in executor.calls] == ["show"]


def test_operation_uses_described_path_parameter_name():
    executor = Executor([{"finished": True, "status": True}])
    action = lookup_action(executor.description, ("action_state",), "show")
    assert action.path_parameters == ("state_id",)
    Operation(executor, 3, 19).show()
    assert executor.calls[0][0].bound_args == (19,)
