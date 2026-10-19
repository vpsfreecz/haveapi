"""Finite response values and explicit, side-effect-free object bindings."""

from __future__ import annotations

from collections.abc import Iterator, Mapping
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import TYPE_CHECKING, Any, Generic, TypeVar, cast

from ._protocol import (
    ActionSpec,
    AsyncExecutor,
    CallContext,
    DecodedResponse,
    SyncExecutor,
    lookup_action,
)
from ._protocol.models import freeze, frozen_mapping
from .exceptions import ProtocolError, StaleDescriptionError, ValidationError

if TYPE_CHECKING:
    from .operations import AsyncOperation, Operation

_T = TypeVar("_T")


@dataclass(frozen=True)
class Response(Generic[_T]):
    data: _T = field(repr=False)
    meta: Mapping[str, object] = field(repr=False)
    status_code: int
    headers: Mapping[str, str] = field(repr=False)
    envelope: Mapping[str, object] = field(repr=False)
    operation: Operation | AsyncOperation | None = None

    def __post_init__(self) -> None:
        object.__setattr__(self, "meta", frozen_mapping(self.meta))
        object.__setattr__(self, "headers", frozen_mapping(self.headers))
        object.__setattr__(self, "envelope", frozen_mapping(self.envelope))


def _identity(value: object) -> bool:
    return isinstance(value, (str, int)) and not isinstance(value, bool)


def _bindings(
    action: ActionSpec,
    context: CallContext,
    values: Mapping[str, object],
    meta: Mapping[str, object],
    *,
    identity_field: str = "id",
    inherit_context: bool = True,
) -> Mapping[str, str | int]:
    names = action.path_parameters
    supplied = meta.get("path_params")
    if supplied is not None:
        if (
            not isinstance(supplied, (list, tuple))
            or len(supplied) != len(names)
            or not all(_identity(v) for v in supplied)
        ):
            raise ProtocolError("object path_params must match the described show path")
        return dict(zip(names, cast(tuple[str | int, ...], supplied), strict=True))
    known: dict[str, str | int] = {}
    if inherit_context:
        known.update(
            zip(context.action.path_parameters, context.bound_args, strict=False)
        )
        known.update(context.path_params)
    result = {name: known[name] for name in names if name in known}
    missing = [name for name in names if name not in result]
    identity = values.get(identity_field)
    if len(missing) == 1 and names and missing[0] == names[-1] and _identity(identity):
        result[missing[0]] = cast(str | int, identity)
    return result


class ResourceObject(Mapping[str, object]):
    """Read-only returned fields; navigation and inspection never fetch data."""

    def __init__(
        self,
        values: Mapping[str, object],
        *,
        meta: Mapping[str, object],
        resource_path: tuple[str, ...],
        context: CallContext,
        executor: SyncExecutor | AsyncExecutor,
        identity_field: str = "id",
        inherit_context: bool = True,
    ) -> None:
        self._fields = MappingProxyType(
            {
                key: value if isinstance(value, ResourceObject) else freeze(value)
                for key, value in values.items()
            }
        )
        self._meta = frozen_mapping(meta)
        self._resource_path = resource_path
        self._context = context
        self._executor = executor
        self._identity_field = identity_field
        self._inherit_context = inherit_context

    def __getitem__(self, key: str) -> object:
        return self._fields[key]

    def __iter__(self) -> Iterator[str]:
        return iter(self._fields)

    def __len__(self) -> int:
        return len(self._fields)

    def __getattr__(self, name: str) -> object:
        if not name.startswith("_") and name in self._fields:
            return self._fields[name]
        raise AttributeError(name)

    def __repr__(self) -> str:
        return f"<{type(self).__name__} resource={self._resource_path!r}>"

    def __dir__(self) -> list[str]:
        return sorted(set(super().__dir__()) | set(self._fields))

    @property
    def meta(self) -> Mapping[str, object]:
        return self._meta

    def _check(self) -> None:
        if self._context.generation != self._executor.generation:
            raise StaleDescriptionError("object belongs to an old description")

    def _show_context(self) -> CallContext:
        self._check()
        try:
            action = lookup_action(
                self._executor.description, self._resource_path, "show"
            )
        except KeyError as error:
            raise ProtocolError(
                "associated resource has no unambiguous show action"
            ) from error
        bindings = _bindings(
            action,
            self._context,
            self._fields,
            self._meta,
            identity_field=self._identity_field,
            inherit_context=self._inherit_context,
        )
        if set(bindings) != set(action.path_parameters):
            raise ValidationError(
                "object identity is incomplete; provide explicit path parameters"
            )
        return CallContext(action, (), bindings, self._context.generation)

    @property
    def resource(self) -> Any:
        self._check()
        try:
            action = lookup_action(
                self._executor.description, self._resource_path, "show"
            )
        except KeyError:
            # A resource may expose only custom actions. Preserve known binding
            # context and let its actual action validate the required parameters.
            if (
                self._inherit_context
                and self._resource_path == self._context.action.resource_path
            ):
                return self._executor.resource(
                    self._resource_path,
                    bound_args=self._context.bound_args,
                    path_params=self._context.path_params,
                )
            return self._executor.resource(self._resource_path)
        bindings = _bindings(
            action,
            self._context,
            self._fields,
            self._meta,
            identity_field=self._identity_field,
            inherit_context=self._inherit_context,
        )
        return self._executor.resource(self._resource_path, path_params=bindings)


class Association(ResourceObject):
    def fetch(self) -> Response[Any]:
        return cast(SyncExecutor, self._executor).execute(self._show_context())


class AsyncAssociation(ResourceObject):
    async def fetch(self) -> Response[Any]:
        return await cast(AsyncExecutor, self._executor).execute(self._show_context())


def _object(
    values: Mapping[str, object],
    context: CallContext,
    executor: SyncExecutor | AsyncExecutor,
    *,
    asynchronous: bool,
    single_meta: Mapping[str, object] | None = None,
) -> ResourceObject:
    namespace = executor.description.meta_namespace
    raw_meta = values.get(namespace, single_meta or {})
    if not isinstance(raw_meta, Mapping):
        raise ProtocolError("object metadata must be an object")
    fields: dict[str, object] = {k: v for k, v in values.items() if k != namespace}
    if context.action.output:
        for name, parameter in context.action.output.parameters.items():
            if parameter.type != "Resource" or fields.get(name) is None:
                continue
            associated = fields[name]
            path = parameter.raw.get("resource")
            if (
                not isinstance(associated, Mapping)
                or not isinstance(path, (list, tuple))
                or not all(isinstance(v, str) for v in path)
            ):
                raise ProtocolError("invalid resource association")
            association_meta = associated.get(namespace, {})
            if not isinstance(association_meta, Mapping):
                raise ProtocolError("invalid association metadata")
            value_id = parameter.raw.get("value_id", "id")
            value_label = parameter.raw.get("value_label", "label")
            if not isinstance(value_id, str) or not isinstance(value_label, str):
                raise ProtocolError("invalid association identity fields")
            association_fields = {k: v for k, v in associated.items() if k != namespace}
            # Expose stable convenience names while retaining exact wire fields.
            association_fields.setdefault("id", associated.get(value_id))
            association_fields.setdefault("label", associated.get(value_label))
            cls = AsyncAssociation if asynchronous else Association
            fields[name] = cls(
                association_fields,
                meta=association_meta,
                resource_path=tuple(path),
                context=context,
                executor=executor,
                identity_field=value_id,
                inherit_context=False,
            )
    return ResourceObject(
        fields,
        meta=raw_meta,
        resource_path=context.action.resource_path,
        context=context,
        executor=executor,
    )


def _adapt(
    decoded: DecodedResponse,
    context: CallContext,
    executor: SyncExecutor | AsyncExecutor,
    *,
    asynchronous: bool,
) -> Response[Any]:
    data = decoded.data
    output = context.action.output
    if output and output.layout == "object":
        if not isinstance(data, Mapping):
            raise ProtocolError("object output must be an object")
        data = _object(
            data, context, executor, asynchronous=asynchronous, single_meta=decoded.meta
        )
    elif output and output.layout == "object_list":
        if not isinstance(data, (list, tuple)):
            raise ProtocolError("object list output must be an array")
        data = tuple(
            _object(item, context, executor, asynchronous=asynchronous) for item in data
        )
    operation = None
    operation_id = decoded.meta.get("action_state_id")
    if context.action.blocking and operation_id is not None:
        if not _identity(operation_id):
            raise ProtocolError("invalid blocking operation identifier")
        from .operations import AsyncOperation, Operation

        cls = AsyncOperation if asynchronous else Operation
        operation = cls(executor, context.generation, cast(str | int, operation_id))
    return Response(
        data,
        decoded.meta,
        decoded.status_code,
        decoded.headers,
        decoded.envelope,
        operation,
    )


def adapt_response(
    decoded: DecodedResponse, context: CallContext, executor: SyncExecutor
) -> Response[Any]:
    return _adapt(decoded, context, executor, asynchronous=False)


def adapt_async_response(
    decoded: DecodedResponse, context: CallContext, executor: AsyncExecutor
) -> Response[Any]:
    return _adapt(decoded, context, executor, asynchronous=True)
