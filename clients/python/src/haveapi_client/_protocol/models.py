"""Immutable protocol descriptions and transport-neutral request state."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import TypeVar, cast

_T = TypeVar("_T")
InputObject = Mapping[str, object]
InputParams = InputObject | Sequence[InputObject]


def freeze(value: object) -> object:
    """Copy JSON-shaped values so descriptions cannot change under active calls."""
    if isinstance(value, Mapping):
        return MappingProxyType({k: freeze(v) for k, v in value.items()})
    if isinstance(value, (list, tuple)):
        return tuple(freeze(v) for v in value)
    return value


def frozen_mapping(value: Mapping[str, _T]) -> Mapping[str, _T]:
    return cast(Mapping[str, _T], freeze(value))


@dataclass(frozen=True)
class ParameterSpec:
    name: str
    type: str
    required: bool
    nullable: bool
    raw: Mapping[str, object] = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "raw", frozen_mapping(self.raw))


@dataclass(frozen=True)
class LayoutSpec:
    layout: str
    namespace: str | None
    parameters: Mapping[str, ParameterSpec]
    raw: Mapping[str, object] = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "parameters", frozen_mapping(self.parameters))
        object.__setattr__(self, "raw", frozen_mapping(self.raw))


@dataclass(frozen=True)
class ActionSpec:
    name: str
    resource_path: tuple[str, ...]
    method: str
    path: str
    path_parameters: tuple[str, ...]
    aliases: tuple[str, ...]
    input: LayoutSpec | None
    output: LayoutSpec | None
    meta: Mapping[str, object] = field(repr=False)
    blocking: bool
    auth: bool
    raw: Mapping[str, object] = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "resource_path", tuple(self.resource_path))
        object.__setattr__(self, "path_parameters", tuple(self.path_parameters))
        object.__setattr__(self, "aliases", tuple(self.aliases))
        object.__setattr__(self, "meta", frozen_mapping(self.meta))
        object.__setattr__(self, "raw", frozen_mapping(self.raw))


@dataclass(frozen=True)
class ResourceSpec:
    name: str
    resource_path: tuple[str, ...]
    resources: Mapping[str, ResourceSpec]
    actions: Mapping[str, ActionSpec]
    raw: Mapping[str, object] = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "resource_path", tuple(self.resource_path))
        object.__setattr__(self, "resources", frozen_mapping(self.resources))
        object.__setattr__(self, "actions", frozen_mapping(self.actions))
        object.__setattr__(self, "raw", frozen_mapping(self.raw))


@dataclass(frozen=True)
class Description:
    protocol_version: str
    api_version: str | None
    resources: Mapping[str, ResourceSpec]
    authentication: Mapping[str, Mapping[str, object]] = field(repr=False)
    meta_namespace: str
    raw: Mapping[str, object] = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "resources", frozen_mapping(self.resources))
        object.__setattr__(self, "authentication", frozen_mapping(self.authentication))
        object.__setattr__(self, "raw", frozen_mapping(self.raw))


@dataclass(frozen=True)
class RequestSpec:
    method: str
    url: str = field(repr=False)
    query: tuple[tuple[str, str], ...] = field(repr=False)
    headers: Mapping[str, str] = field(repr=False)
    content: bytes | None = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "query", tuple(tuple(v) for v in self.query))
        object.__setattr__(self, "headers", frozen_mapping(self.headers))


@dataclass(frozen=True)
class WireResponse:
    status_code: int
    headers: Mapping[str, str] = field(repr=False)
    content: bytes = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "headers", frozen_mapping(self.headers))


@dataclass(frozen=True)
class DecodedResponse:
    data: object = field(repr=False)
    meta: Mapping[str, object] = field(repr=False)
    envelope: Mapping[str, object] = field(repr=False)
    status_code: int
    headers: Mapping[str, str] = field(repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "meta", frozen_mapping(self.meta))
        object.__setattr__(self, "envelope", frozen_mapping(self.envelope))
        object.__setattr__(self, "headers", frozen_mapping(self.headers))


@dataclass(frozen=True)
class CallContext:
    action: ActionSpec
    bound_args: tuple[str | int, ...] = field(repr=False)
    path_params: Mapping[str, str | int] = field(repr=False)
    generation: int

    def __post_init__(self) -> None:
        object.__setattr__(self, "bound_args", tuple(self.bound_args))
        object.__setattr__(self, "path_params", frozen_mapping(self.path_params))


@dataclass(frozen=True)
class RequestOptions:
    timeout: float | None = None

    def __post_init__(self) -> None:
        import math

        if self.timeout is not None and (
            isinstance(self.timeout, bool)
            or not math.isfinite(self.timeout)
            or self.timeout <= 0
        ):
            raise ValueError("timeout must be positive and finite")
