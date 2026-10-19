import pytest

from haveapi_client._protocol import CallContext, lookup_action, parse_description
from haveapi_client.exceptions import PaginationError
from haveapi_client.pagination import (
    IdCursor,
    aiter_all,
    aiter_pages,
    iter_all,
    iter_pages,
)
from haveapi_client.response import Response


class Executor:
    def __init__(self, pages):
        self.generation = 1
        self.description = parse_description(
            {
                "status": True,
                "version": "2.0",
                "response": {
                    "resources": {
                        "row": {
                            "actions": {
                                "index": {
                                    "path": "/v1/rows",
                                    "method": "GET",
                                    "input": {
                                        "layout": "hash",
                                        "namespace": "row",
                                        "parameters": {
                                            k: {"type": "Integer"}
                                            for k in ("limit", "from_id")
                                        },
                                    },
                                    "output": {
                                        "layout": "object_list",
                                        "namespace": "rows",
                                        "parameters": {},
                                    },
                                }
                            }
                        }
                    }
                },
            }
        )
        self.pages = iter(pages)
        self.calls = []

    def resource(self, *args, **kwargs):
        raise AssertionError("pagination does not navigate resources")

    def execute(self, context, **kwargs):
        self.calls.append(kwargs)
        return Response(next(self.pages), {"page": len(self.calls)}, 200, {}, {})

    def context(self):
        return CallContext(
            lookup_action(self.description, ("row",), "index"), (), {}, 1
        )


class AsyncExecutor(Executor):
    async def execute(self, context, **kwargs):
        return super().execute(context, **kwargs)


def test_short_pages_continue_until_empty_preserving_filters_and_metadata():
    executor = Executor([[{"id": 2}], [{"id": 5}], []])
    params = {"filter": "kept", "from_id": 1}
    pages = list(
        iter_pages(
            executor,
            executor.context(),
            strategy=IdCursor(),
            page_size=2,
            params=params,
            meta={"count": True},
        )
    )
    assert [len(page.data) for page in pages] == [1, 1, 0]
    assert [call["params"]["from_id"] for call in executor.calls] == [1, 2, 5]
    assert all(
        call["params"]["filter"] == "kept"
        and call["params"]["limit"] == 2
        and call["meta"]["count"]
        for call in executor.calls
    )
    assert params == {"filter": "kept", "from_id": 1}


@pytest.mark.parametrize(
    "pages",
    [[[{}]], [[{"id": 2}, {"id": 1}]], [[{"id": 2}], [{"id": 2}]], [[{"id": True}]]],
)
def test_invalid_cursor_pages_fail_locally(pages):
    executor = Executor(pages)
    with pytest.raises(PaginationError):
        list(iter_all(executor, executor.context(), strategy=IdCursor()))


def test_explicit_descending_direction():
    executor = Executor([[{"id": 9}, {"id": 7}], [{"id": 4}], []])
    assert [
        item["id"]
        for item in iter_all(
            executor, executor.context(), strategy=IdCursor(direction="desc")
        )
    ] == [9, 7, 4]


@pytest.mark.parametrize("page_size", [0, -1, True, 1.5])
def test_page_size_is_positive_integer(page_size):
    executor = Executor([])
    with pytest.raises(PaginationError):
        list(
            iter_pages(
                executor, executor.context(), strategy=IdCursor(), page_size=page_size
            )
        )
    assert not executor.calls


def test_custom_strategy_repetition_detected_without_numeric_assumptions():
    class Custom:
        parameter = "from_id"

        def next_cursor(self, page, previous):
            return "same"

    executor = Executor([[{"id": 1}], [{"id": 2}]])
    with pytest.raises(PaginationError, match="repeated"):
        list(iter_pages(executor, executor.context(), strategy=Custom()))


@pytest.mark.anyio
async def test_async_pages_and_items_have_same_progression():
    executor = AsyncExecutor([[{"id": 1}], [{"id": 2}], []])
    assert [
        item["id"]
        async for item in aiter_all(executor, executor.context(), strategy=IdCursor())
    ] == [1, 2]
    executor = AsyncExecutor([[{"id": 1}], []])
    assert [
        len(page.data)
        async for page in aiter_pages(executor, executor.context(), strategy=IdCursor())
    ] == [1, 0]
