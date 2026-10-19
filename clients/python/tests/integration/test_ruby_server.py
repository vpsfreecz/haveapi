"""Contract checks against the shared server used by the other clients."""

from __future__ import annotations

import pytest

from haveapi_client._auth import (
    AsyncAuthenticationChallenge,
    Authenticated,
    AuthenticationChallenge,
    BasicAuth,
)
from haveapi_client.async_client import AsyncClient
from haveapi_client.client import Client
from haveapi_client.exceptions import OperationFailedError, OperationTimeoutError

pytestmark = pytest.mark.integration


def test_authorized_rediscovery_and_nested_write(server_url: str) -> None:
    with Client(server_url) as client:
        assert "project" not in client.resources
        client.set_auth(BasicAuth("user", "pass"))
        result = client.resources["project"].actions["index"].call(meta={"count": True})
        projects = result.data
        assert result.status_code == 200
        assert result.meta["total_count"] == 2
        assert [project["name"] for project in projects] == ["Alpha", "Beta"]
        task = (
            client.resource(("project", "task"), bound_args=(1,))
            .actions["create"]
            .call(params={"label": "Python integration task"})
        )
        assert task.data["label"] == "Python integration task"
        client.logout()
        assert "project" not in client.resources


def test_token_lifecycle(server_url: str) -> None:
    with Client(server_url) as client:
        outcome = client.begin_token_login(
            {"user": "user", "password": "pass", "lifetime": "renewable_manual"}
        )
        assert isinstance(outcome, Authenticated)
        assert outcome.token
        assert client.resources["project"].actions["index"].call().data
        client.renew_token()
        client.revoke_token()
        assert "project" not in client.resources


@pytest.mark.anyio
async def test_async_discovery_and_nested_read(server_url: str) -> None:
    async with AsyncClient(server_url, auth=BasicAuth("user", "pass")) as client:
        response = await client.resources["project"].actions["index"].call()
        assert [project["name"] for project in response.data] == ["Alpha", "Beta"]
        task = (
            await client.resource(("project", "task"), bound_args=(1,))
            .actions["show"]
            .call(path_params={"task_id": 1})
        )
        assert task.data["label"] == "Initial task"


def test_generic_advertised_authentication_challenge(server_url: str) -> None:
    with Client(server_url) as client:
        challenge = client.begin_token_login(
            {
                "user": "user",
                "password": "pass",
                "lifetime": "renewable_manual",
                "phrase_challenge": True,
            }
        )
        assert isinstance(challenge, AuthenticationChallenge)
        assert challenge.next_action == "verify_phrase"
        assert set(challenge.input) == {"phrase"}
        outcome = challenge.submit({"phrase": "violet otter"})
        assert isinstance(outcome, Authenticated)
        assert client.resources["project"].actions["index"].call().data


@pytest.mark.anyio
async def test_async_generic_advertised_authentication_challenge(
    server_url: str,
) -> None:
    async with AsyncClient(server_url) as client:
        challenge = await client.begin_token_login(
            {
                "user": "user",
                "password": "pass",
                "lifetime": "renewable_manual",
                "phrase_challenge": True,
            }
        )
        assert isinstance(challenge, AsyncAuthenticationChallenge)
        assert challenge.next_action == "verify_phrase"
        assert set(challenge.input) == {"phrase"}
        outcome = await challenge.submit({"phrase": "violet otter"})
        assert isinstance(outcome, Authenticated)
        assert (await client.resources["project"].actions["index"].call()).data


def test_blocking_operation_monitoring_and_cancel(server_url: str) -> None:
    with Client(server_url, auth=BasicAuth("user", "pass")) as client:
        task = client.resource(("project", "task"), bound_args=(1, 1))
        operation = task.actions["run"]().operation
        assert operation is not None
        assert operation.show().data["finished"] is False
        with pytest.raises(OperationTimeoutError):
            operation.wait(timeout=0.05, interval=0.01)
        # This shared fixture advances only through its advertised poll action.
        state = client.resources["action_state"][operation.action_state_id]
        for _ in range(3):
            state.actions["poll"](timeout=1)
        completed = operation.wait(timeout=2, interval=0.01)
        assert completed.data["finished"] is True
        assert completed.data["status"] is True
        cancelled = task.actions["run"]().operation
        assert cancelled is not None
        cancelled.cancel()
        with pytest.raises(OperationFailedError):
            cancelled.wait(timeout=2, interval=0.01)


@pytest.mark.anyio
async def test_async_blocking_operation_monitoring_and_cancel(server_url: str) -> None:
    async with AsyncClient(server_url, auth=BasicAuth("user", "pass")) as client:
        task = client.resource(("project", "task"), bound_args=(1, 1))
        operation = (await task.actions["run"]()).operation
        assert operation is not None
        assert (await operation.show()).data["finished"] is False
        with pytest.raises(OperationTimeoutError):
            await operation.wait(timeout=0.05, interval=0.01)
        state = client.resources["action_state"][operation.action_state_id]
        for _ in range(3):
            await state.actions["poll"](timeout=1)
        completed = await operation.wait(timeout=2, interval=0.01)
        assert completed.data["finished"] is True
        assert completed.data["status"] is True
        cancelled = (await task.actions["run"]()).operation
        assert cancelled is not None
        await cancelled.cancel()
        with pytest.raises(OperationFailedError):
            await cancelled.wait(timeout=2, interval=0.01)


def test_get_dense_rows_and_delete_json_round_trip(server_url: str) -> None:
    with Client(server_url) as client:
        dense_rows = [{"a": "one&=+", "b": "žluť /[]"}, {"b": "last", "a": "3"}]
        result = client.wire.get_rows.call(
            params={
                "rows": dense_rows,
                "message": "雪&/[]=+?",
                "count": 2,
                "flag": False,
            },
            meta={"marker": "marker&=1"},
        )
        assert result.data["rows"] == dense_rows
        assert result.data["message"] == "雪&/[]=+?"
        assert result.data["count"] == 2
        assert result.data["flag"] is False
        assert result.data["marker"] == "marker&=1"
        json_rows = [{"a": []}, {"b": {"empty": {}, "values": [False, 2, None]}}]
        deleted = client.wire.delete_payload.call(
            params={"rows": json_rows, "message": "delete body"},
            meta={"marker": "delete metadata"},
        )
        assert deleted.data["rows"] == json_rows
        assert deleted.data["message"] == "delete body"
        assert deleted.data["marker"] == "delete metadata"


@pytest.mark.anyio
async def test_async_get_dense_rows_and_delete_json_round_trip(server_url: str) -> None:
    async with AsyncClient(server_url) as client:
        dense_rows = [{"a": "one&=+", "b": "žluť /[]"}, {"b": "last", "a": "3"}]
        result = await client.wire.get_rows.call(
            params={
                "rows": dense_rows,
                "message": "雪&/[]=+?",
                "count": 2,
                "flag": False,
            },
            meta={"marker": "marker&=1"},
        )
        assert result.data["rows"] == dense_rows
        assert result.data["message"] == "雪&/[]=+?"
        assert result.data["count"] == 2
        assert result.data["flag"] is False
        assert result.data["marker"] == "marker&=1"
        json_rows = [{"a": []}, {"b": {"empty": {}, "values": [False, 2, None]}}]
        deleted = await client.wire.delete_payload.call(
            params={"rows": json_rows, "message": "delete body"},
            meta={"marker": "delete metadata"},
        )
        assert deleted.data["rows"] == json_rows
        assert deleted.data["message"] == "delete body"
        assert deleted.data["marker"] == "delete metadata"
