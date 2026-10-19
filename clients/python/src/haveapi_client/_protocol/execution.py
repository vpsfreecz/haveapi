"""Execution boundary shared by the facade and response helpers."""

from __future__ import annotations

from collections.abc import Mapping
from typing import TYPE_CHECKING, Any, Protocol

from .models import CallContext, Description, InputParams, RequestOptions

if TYPE_CHECKING:
    from ..response import Response


class SyncExecutor(Protocol):
    @property
    def description(self) -> Description: ...

    @property
    def generation(self) -> int: ...

    def resource(
        self,
        path: tuple[str, ...],
        *,
        bound_args: tuple[str | int, ...] = (),
        path_params: Mapping[str, str | int] | None = None,
    ) -> Any: ...

    def execute(
        self,
        context: CallContext,
        *,
        params: InputParams | None = None,
        meta: Mapping[str, object] | None = None,
        options: RequestOptions | None = None,
    ) -> Response[Any]: ...


class AsyncExecutor(Protocol):
    @property
    def description(self) -> Description: ...

    @property
    def generation(self) -> int: ...

    def resource(
        self,
        path: tuple[str, ...],
        *,
        bound_args: tuple[str | int, ...] = (),
        path_params: Mapping[str, str | int] | None = None,
    ) -> Any: ...

    async def execute(
        self,
        context: CallContext,
        *,
        params: InputParams | None = None,
        meta: Mapping[str, object] | None = None,
        options: RequestOptions | None = None,
    ) -> Response[Any]: ...
