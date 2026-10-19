"""Immutable resource and action navigation; only calls perform I/O."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import Any

from haveapi_client._protocol import (
    CallContext,
    InputParams,
    RequestOptions,
    lookup_action,
    lookup_resource,
)
from haveapi_client.exceptions import StaleDescriptionError


def _path_params(
    old: Mapping[str, str | int], new: Mapping[str, str | int] | None
) -> Mapping[str, str | int]:
    result = dict(old)
    for key, value in (new or {}).items():
        if key in result and result[key] != value:
            raise ValueError(f"Conflicting path parameter: {key}")
        result[key] = value
    return MappingProxyType(result)


@dataclass(frozen=True)
class Resource:
    _executor: Any = field(repr=False, compare=False)
    _path: tuple[str, ...]
    _bound_args: tuple[str | int, ...] = field(default=(), repr=False)
    _path_params: Mapping[str, str | int] = field(default_factory=dict, repr=False)
    _generation: int = 0
    _async: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "_path", tuple(self._path))
        object.__setattr__(self, "_bound_args", tuple(self._bound_args))
        object.__setattr__(
            self, "_path_params", MappingProxyType(dict(self._path_params))
        )

    def _check(self) -> None:
        if self._executor.generation != self._generation:
            raise StaleDescriptionError("Resource belongs to an old description")

    @property
    def resources(self) -> Mapping[str, Resource]:
        self._check()
        spec = lookup_resource(self._executor.description, self._path)
        return MappingProxyType(
            {
                name: Resource(
                    self._executor,
                    child.resource_path,
                    self._bound_args,
                    self._path_params,
                    self._generation,
                    self._async,
                )
                for name, child in spec.resources.items()
            }
        )

    @property
    def actions(self) -> Mapping[str, Action]:
        self._check()
        spec = lookup_resource(self._executor.description, self._path)
        return MappingProxyType({name: self._action(name) for name in spec.actions})

    def _action(self, name: str) -> Action:
        self._check()
        spec = lookup_action(self._executor.description, self._path, name)
        return Action(
            self._executor,
            CallContext(spec, self._bound_args, self._path_params, self._generation),
            self._async,
        )

    def __getattr__(self, name: str) -> Any:
        if name.startswith("_"):
            raise AttributeError(name)
        self._check()
        spec = lookup_resource(self._executor.description, self._path)
        has_action = name in spec.actions or any(
            name in a.aliases for a in spec.actions.values()
        )
        if name in spec.resources:
            if has_action:
                raise AttributeError(
                    f"Ambiguous resource/action {name!r}; use exact-name maps"
                )
            return self.resources[name]
        if has_action:
            return self._action(name)
        raise AttributeError(name)

    def __getitem__(self, value: str | int) -> Resource:
        self._check()
        if isinstance(value, bool) or not isinstance(value, (str, int)):
            raise TypeError("Path bindings must be strings or integers")
        return Resource(
            self._executor,
            self._path,
            (*self._bound_args, value),
            self._path_params,
            self._generation,
            self._async,
        )

    def __dir__(self) -> list[str]:
        self._check()
        spec = lookup_resource(self._executor.description, self._path)
        return sorted(set(super().__dir__()) | set(spec.resources) | set(spec.actions))


@dataclass(frozen=True)
class Action:
    _executor: Any = field(repr=False, compare=False)
    _context: CallContext = field(repr=False)
    _async: bool = False

    def _binding(self, path_params: Mapping[str, str | int] | None) -> CallContext:
        if self._executor.generation != self._context.generation:
            raise StaleDescriptionError("Action belongs to an old description")
        return CallContext(
            self._context.action,
            self._context.bound_args,
            _path_params(self._context.path_params, path_params),
            self._context.generation,
        )

    def __call__(self, **params: object) -> Any:
        return self.call(params=params)

    def call(
        self,
        *,
        params: InputParams | None = None,
        meta: Mapping[str, object] | None = None,
        path_params: Mapping[str, str | int] | None = None,
        options: RequestOptions | None = None,
    ) -> Any:
        return self._executor.execute(
            self._binding(path_params), params=params, meta=meta, options=options
        )

    def iter_pages(
        self,
        *,
        strategy: Any,
        page_size: int = 100,
        params: Mapping[str, object] | None = None,
        meta: Mapping[str, object] | None = None,
        path_params: Mapping[str, str | int] | None = None,
        options: RequestOptions | None = None,
    ) -> Any:
        from haveapi_client.pagination import aiter_pages, iter_pages

        function = aiter_pages if self._async else iter_pages
        return function(
            self._executor,
            self._binding(path_params),
            strategy=strategy,
            page_size=page_size,
            params=params,
            meta=meta,
            options=options,
        )

    def iter_all(
        self,
        *,
        strategy: Any,
        page_size: int = 100,
        params: Mapping[str, object] | None = None,
        meta: Mapping[str, object] | None = None,
        path_params: Mapping[str, str | int] | None = None,
        options: RequestOptions | None = None,
    ) -> Any:
        from haveapi_client.pagination import aiter_all, iter_all

        function = aiter_all if self._async else iter_all
        return function(
            self._executor,
            self._binding(path_params),
            strategy=strategy,
            page_size=page_size,
            params=params,
            meta=meta,
            options=options,
        )
