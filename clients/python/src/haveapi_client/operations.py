"""Explicit monitoring of HaveAPI action_state operations."""

from __future__ import annotations

import math
import time
from collections.abc import Mapping
from typing import Any, cast

import anyio

from ._protocol import (
    AsyncExecutor,
    CallContext,
    RequestOptions,
    SyncExecutor,
    lookup_action,
)
from .exceptions import (
    OperationFailedError,
    OperationTimeoutError,
    ProtocolError,
    StaleDescriptionError,
    TransportError,
)
from .response import Response


def _positive(value: float, name: str) -> None:
    if isinstance(value, bool) or not math.isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be positive and finite")


class _Operation:
    def __init__(
        self,
        executor: SyncExecutor | AsyncExecutor,
        generation: int,
        action_state_id: str | int,
    ) -> None:
        if isinstance(action_state_id, bool) or not isinstance(
            action_state_id, (str, int)
        ):
            raise ValueError("operation ID must be a string or integer")
        self._executor = executor
        self._generation = generation
        self.action_state_id = action_state_id

    def __repr__(self) -> str:
        return f"<{type(self).__name__} id={self.action_state_id!r}>"

    def _context(self, name: str) -> CallContext:
        if self._generation != self._executor.generation:
            raise StaleDescriptionError(
                "operation belongs to an old description",
                operation_id=self.action_state_id,
            )
        try:
            action = lookup_action(self._executor.description, ("action_state",), name)
        except KeyError as error:
            raise ProtocolError(
                f"operation action is unavailable: {name}",
                operation_id=self.action_state_id,
            ) from error
        if len(action.path_parameters) != 1:
            raise ProtocolError(
                "operation action must have one ID path parameter",
                operation_id=self.action_state_id,
            )
        return CallContext(action, (self.action_state_id,), {}, self._generation)

    def _terminal(self, response: Response[Any]) -> bool:
        state = response.data
        if not isinstance(state, Mapping) or not isinstance(
            state.get("finished"), bool
        ):
            raise ProtocolError(
                "operation response has no boolean finished state",
                operation_id=self.action_state_id,
            )
        if state["finished"] is False:
            return False
        if state.get("status") is False:
            raise OperationFailedError(
                "operation finished unsuccessfully",
                status_code=response.status_code,
                envelope=response.envelope,
                operation_id=self.action_state_id,
            )
        if state.get("status") is not True:
            raise ProtocolError(
                "finished operation has no boolean result status",
                operation_id=self.action_state_id,
            )
        return True

    def _remaining(self, deadline: float) -> float:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise OperationTimeoutError(
                "operation wait timed out", operation_id=self.action_state_id
            )
        return remaining

    def _cancellable(self, response: Response[Any]) -> None:
        if (
            not isinstance(response.data, Mapping)
            or response.data.get("can_cancel") is not True
        ):
            raise OperationFailedError(
                "operation cannot be cancelled", operation_id=self.action_state_id
            )


class Operation(_Operation):
    def show(self) -> Response[Any]:
        return cast(SyncExecutor, self._executor).execute(self._context("show"))

    def wait(self, *, timeout: float = 300.0, interval: float = 1.0) -> Response[Any]:
        """Wait locally, leaving the server operation running on timeout.

        HTTPX applies the remaining budget to individual transport phases. A
        blocking request can return control after the overall deadline; classify
        its result or failure against the monotonic deadline once it returns.
        """
        _positive(timeout, "timeout")
        _positive(interval, "interval")
        deadline = time.monotonic() + timeout
        while True:
            remaining = self._remaining(deadline)
            try:
                response = cast(SyncExecutor, self._executor).execute(
                    self._context("show"), options=RequestOptions(timeout=remaining)
                )
            except TransportError as error:
                try:
                    self._remaining(deadline)
                except OperationTimeoutError as expired:
                    raise expired from error
                raise
            self._remaining(deadline)
            if self._terminal(response):
                return response
            time.sleep(min(interval, self._remaining(deadline)))

    def cancel(self) -> Response[Any]:
        context = self._context("cancel")
        self._cancellable(self.show())
        return cast(SyncExecutor, self._executor).execute(context)


class AsyncOperation(_Operation):
    async def show(self) -> Response[Any]:
        return await cast(AsyncExecutor, self._executor).execute(self._context("show"))

    async def wait(
        self, *, timeout: float = 300.0, interval: float = 1.0
    ) -> Response[Any]:
        _positive(timeout, "timeout")
        _positive(interval, "interval")
        deadline = time.monotonic() + timeout
        while True:
            remaining = self._remaining(deadline)
            scope = None
            try:
                with anyio.fail_after(remaining) as scope:
                    response = await cast(AsyncExecutor, self._executor).execute(
                        self._context("show"), options=RequestOptions(timeout=remaining)
                    )
            except TimeoutError as error:
                if scope is not None and scope.cancelled_caught:
                    raise OperationTimeoutError(
                        "operation wait timed out", operation_id=self.action_state_id
                    ) from error
                raise
            except TransportError as error:
                try:
                    self._remaining(deadline)
                except OperationTimeoutError as expired:
                    raise expired from error
                raise
            self._remaining(deadline)
            if self._terminal(response):
                return response
            await anyio.sleep(min(interval, self._remaining(deadline)))

    async def cancel(self) -> Response[Any]:
        context = self._context("cancel")
        self._cancellable(await self.show())
        return await cast(AsyncExecutor, self._executor).execute(context)
