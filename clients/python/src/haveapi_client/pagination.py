"""Explicit cursor iteration; a normal action response remains one finite page."""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterator, Mapping, Sequence
from dataclasses import dataclass
from typing import Any, Protocol

from ._protocol import AsyncExecutor, CallContext, RequestOptions, SyncExecutor
from ._protocol.models import frozen_mapping
from .exceptions import PaginationError, StaleDescriptionError
from .response import Response


class CursorStrategy(Protocol):
    @property
    def parameter(self) -> str: ...

    def next_cursor(
        self, page: Response[Any], previous: object | None
    ) -> object | None: ...


def _items(page: Response[Any]) -> Sequence[Any]:
    if not isinstance(page.data, (list, tuple)):
        raise PaginationError("pagination requires a finite list response")
    return page.data


@dataclass(frozen=True)
class IdCursor:
    parameter: str = "from_id"
    field: str = "id"
    direction: str = "asc"

    def __post_init__(self) -> None:
        if self.direction not in ("asc", "desc"):
            raise ValueError("cursor direction must be asc or desc")
        if not self.parameter or not self.field:
            raise ValueError("cursor parameter and field must be nonempty")

    def next_cursor(
        self, page: Response[Any], previous: object | None
    ) -> object | None:
        items = _items(page)
        if not items:
            return None
        if previous is not None and (
            not isinstance(previous, int) or isinstance(previous, bool)
        ):
            raise PaginationError("IdCursor requires integer cursors")
        last = previous
        for item in items:
            value = item.get(self.field) if isinstance(item, Mapping) else None
            if not isinstance(value, int) or isinstance(value, bool):
                raise PaginationError(
                    f"page item has no integer cursor field: {self.field}"
                )
            if last is not None and (
                value <= last if self.direction == "asc" else value >= last
            ):
                raise PaginationError("cursor did not progress monotonically")
            last = value
        return last


def _prepare(
    context: CallContext,
    strategy: CursorStrategy,
    page_size: int,
    params: Mapping[str, object] | None,
) -> dict[str, object]:
    if isinstance(page_size, bool) or not isinstance(page_size, int) or page_size <= 0:
        raise PaginationError("page_size must be a positive integer")
    action = context.action
    if not action.output or action.output.layout not in ("object_list", "hash_list"):
        raise PaginationError("pagination requires object_list or hash_list output")
    if not action.input or action.input.layout not in ("object", "hash"):
        raise PaginationError("pagination requires object-shaped input")
    if not isinstance(strategy.parameter, str) or not strategy.parameter:
        raise PaginationError("strategy must declare a cursor parameter")
    if not {"limit", strategy.parameter} <= action.input.parameters.keys():
        raise PaginationError("action does not advertise limit and cursor parameters")
    result = dict(frozen_mapping(params or {}))
    result["limit"] = page_size
    return result


def _next(
    strategy: CursorStrategy,
    page: Response[Any],
    previous: object | None,
    seen: list[object],
) -> object | None:
    if not _items(page):
        return None
    cursor = strategy.next_cursor(page, previous)
    if cursor is None:
        return None
    if any(cursor == old for old in seen):
        raise PaginationError("cursor repeated without progress")
    seen.append(cursor)
    return cursor


def iter_pages(
    executor: SyncExecutor,
    context: CallContext,
    *,
    strategy: CursorStrategy,
    page_size: int = 100,
    params: Mapping[str, object] | None = None,
    meta: Mapping[str, object] | None = None,
    options: RequestOptions | None = None,
) -> Iterator[Response[Any]]:
    inputs = _prepare(context, strategy, page_size, params)
    metadata = frozen_mapping(meta) if meta is not None else None
    cursor = inputs.get(strategy.parameter)
    seen = [cursor] if cursor is not None else []
    while True:
        if executor.generation != context.generation:
            raise StaleDescriptionError("pagination belongs to an old description")
        page = executor.execute(context, params=inputs, meta=metadata, options=options)
        following = _next(strategy, page, cursor, seen)
        yield page
        if following is None:
            return
        cursor = following
        inputs = {**inputs, strategy.parameter: cursor}


def iter_all(
    executor: SyncExecutor,
    context: CallContext,
    *,
    strategy: CursorStrategy,
    page_size: int = 100,
    params: Mapping[str, object] | None = None,
    meta: Mapping[str, object] | None = None,
    options: RequestOptions | None = None,
) -> Iterator[Any]:
    for page in iter_pages(
        executor,
        context,
        strategy=strategy,
        page_size=page_size,
        params=params,
        meta=meta,
        options=options,
    ):
        yield from _items(page)


async def aiter_pages(
    executor: AsyncExecutor,
    context: CallContext,
    *,
    strategy: CursorStrategy,
    page_size: int = 100,
    params: Mapping[str, object] | None = None,
    meta: Mapping[str, object] | None = None,
    options: RequestOptions | None = None,
) -> AsyncIterator[Response[Any]]:
    inputs = _prepare(context, strategy, page_size, params)
    metadata = frozen_mapping(meta) if meta is not None else None
    cursor = inputs.get(strategy.parameter)
    seen = [cursor] if cursor is not None else []
    while True:
        if executor.generation != context.generation:
            raise StaleDescriptionError("pagination belongs to an old description")
        page = await executor.execute(
            context, params=inputs, meta=metadata, options=options
        )
        following = _next(strategy, page, cursor, seen)
        yield page
        if following is None:
            return
        cursor = following
        inputs = {**inputs, strategy.parameter: cursor}


async def aiter_all(
    executor: AsyncExecutor,
    context: CallContext,
    *,
    strategy: CursorStrategy,
    page_size: int = 100,
    params: Mapping[str, object] | None = None,
    meta: Mapping[str, object] | None = None,
    options: RequestOptions | None = None,
) -> AsyncIterator[Any]:
    async for page in aiter_pages(
        executor,
        context,
        strategy=strategy,
        page_size=page_size,
        params=params,
        meta=meta,
        options=options,
    ):
        for item in _items(page):
            yield item
