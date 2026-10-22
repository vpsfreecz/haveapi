"""HaveAPI URL binding and namespaced JSON/bracket-query encoding."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Literal
from urllib.parse import quote, unquote, urlsplit, urlunsplit

from ..exceptions import ProtocolError, ValidationError
from .description import PATH_PARAMETER, mapping, parse_layout
from .input import coerce_input
from .models import CallContext, Description, InputParams, LayoutSpec, RequestSpec


def resolve_url(
    base_url: str, path: str, *, path_mode: Literal["api", "descriptor"] = "api"
) -> str:
    """Resolve discovery under the API base or a described route at its origin."""
    try:
        base = urlsplit(base_url)
        target = urlsplit(path)
        port = base.port
    except ValueError as error:
        raise ProtocolError("invalid endpoint URL") from error
    if (
        base.scheme not in ("http", "https")
        or not base.hostname
        or base.username is not None
        or base.password is not None
        or base.query
        or base.fragment
        or port is not None
        and not 0 < port <= 65535
    ):
        raise ProtocolError(
            "base URL must be an HTTP(S) origin and optional mount path"
        )
    if (
        target.scheme
        or target.netloc
        or path.startswith("//")
        or target.query
        or target.fragment
        or any(ord(c) < 32 or ord(c) == 127 for c in path)
        or "\\" in path
        or path_mode == "descriptor"
        and not path.startswith("/")
    ):
        raise ProtocolError(
            "action endpoint must be an origin-root-relative path"
            if path_mode == "descriptor"
            else "action endpoint must be an API-relative path"
        )
    for candidate in (base.path, target.path):
        # Multiple decoding rounds also reject nested encoded traversal.
        checked = candidate
        for _ in range(8):
            if any(segment in (".", "..") for segment in checked.split("/")):
                raise ProtocolError("path traversal is not allowed")
            decoded = unquote(checked)
            if decoded == checked:
                break
            checked = decoded
        if "\\" in checked or checked.startswith("//"):
            raise ProtocolError("unsafe endpoint path")
    resolved = (
        target.path
        if path_mode == "descriptor"
        else base.path.rstrip("/") + "/" + target.path.lstrip("/")
    )
    return urlunsplit((base.scheme, base.netloc, resolved, "", ""))


def _path_value(value: object) -> str:
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        raise ValidationError("path values must be strings or integers")
    if value == "":
        raise ValidationError("path values cannot be empty")
    # A dot segment remains unsafe even when quoted: common HTTP stacks normalize it.
    if value in (".", ".."):
        raise ValidationError("path values cannot be traversal segments")
    return quote(str(value), safe="", encoding="utf-8", errors="strict")


def _bind(context: CallContext) -> str:
    names = context.action.path_parameters
    if len(context.bound_args) > len(names):
        raise ValidationError("too many positional path bindings")
    bindings = dict(zip(names, context.bound_args, strict=False))
    for name, value in context.path_params.items():
        if name not in names:
            raise ValidationError(f"unknown path parameter: {name}")
        if name in bindings and (
            type(bindings[name]) is not type(value) or bindings[name] != value
        ):
            raise ValidationError(f"conflicting path parameter: {name}")
        bindings[name] = value
    missing = [name for name in names if name not in bindings]
    if missing:
        raise ValidationError(
            "missing path parameters", errors={k: ["missing"] for k in missing}
        )
    return PATH_PARAMETER.sub(
        lambda m: _path_value(bindings[m[1]]), context.action.path
    )


def _query_error(path: str, message: str) -> ValidationError:
    return ValidationError(
        "input cannot be represented by a GET query", errors={path: [message]}
    )


def _query_component(value: str, path: str) -> None:
    if not value or "[" in value or "]" in value:
        raise _query_error(
            path, "query key components must be nonempty and bracket-free"
        )


def _query_value(
    value: object, key: str, *, empty_wrappers: frozenset[str] = frozenset()
) -> list[tuple[str, str]]:
    if isinstance(value, Mapping):
        if not value and key not in empty_wrappers:
            raise _query_error(key, "empty objects cannot be represented")
        pairs = []
        for name, item in value.items():
            path = f"{key}[{name}]"
            _query_component(name, path)
            pairs.extend(_query_value(item, path, empty_wrappers=empty_wrappers))
        return pairs
    if isinstance(value, (list, tuple)):
        if not value:
            raise _query_error(key, "empty arrays cannot be represented")
        if all(isinstance(item, str) for item in value):
            return [(f"{key}[]", item) for item in value]
        if not isinstance(value[0], Mapping) or not value[0]:
            raise _query_error(
                f"{key}[0]", "expected strings or dense flat object rows"
            )
        names = sorted(value[0])
        pairs = []
        for index, row in enumerate(value):
            path = f"{key}[{index}]"
            if not isinstance(row, Mapping) or set(row) != set(names):
                raise _query_error(path, "object rows must have the same nonempty keys")
            for name in names:
                _query_component(name, f"{path}[{name}]")
                item = row[name]
                if isinstance(item, (Mapping, list, tuple)):
                    raise _query_error(
                        f"{path}[{name}]", "object row fields must be scalar"
                    )
                # Repeating every field in one shared order delimits dense Rack
                # rows. Sparse rows or nested values cannot supply that boundary.
                pairs.extend(_query_value(item, f"{key}[][{name}]"))
        return pairs
    if value is None:
        return [(key, "")]
    if isinstance(value, bool):
        return [(key, "true" if value else "false")]
    return [(key, str(value))]


def _query_custom(value: object, path: str, *, nullable: bool = False) -> None:
    if nullable and value is None:
        return
    if isinstance(value, Mapping):
        for name, item in value.items():
            _query_custom(item, f"{path}[{name}]")
    elif isinstance(value, (list, tuple)):
        for index, item in enumerate(value):
            _query_custom(item, f"{path}[{index}]")
    elif not isinstance(value, str):
        raise _query_error(path, "Custom query values must have string leaves")


def _query_custom_input(
    layout: LayoutSpec | None,
    payload: InputParams,
    path: str,
    *,
    object_meta: LayoutSpec | None = None,
    meta_namespace: str = "_meta",
) -> None:
    if layout is None:
        return
    rows = (
        [(path, payload)]
        if isinstance(payload, Mapping)
        else [(f"{path}[{index}]", row) for index, row in enumerate(payload)]
    )
    for row_path, row in rows:
        if not isinstance(row, Mapping):
            continue  # Layout coercion owns malformed row diagnostics.
        for name, spec in layout.parameters.items():
            if spec.type == "Custom" and name in row:
                _query_custom(row[name], f"{row_path}[{name}]", nullable=spec.nullable)
        if object_meta and meta_namespace in row:
            _query_custom_input(
                object_meta,
                mapping(row[meta_namespace], "object metadata"),
                f"{row_path}[{meta_namespace}]",
            )


def _coerce_with_object_meta(
    description: Description, context: CallContext, params: InputParams | None
) -> InputParams:
    layout = context.action.input
    scope = context.action.meta.get("object")
    if layout is None or not isinstance(scope, Mapping) or scope.get("input") is None:
        return coerce_input(layout, params)
    object_layout = parse_layout(scope["input"])
    namespace = description.meta_namespace

    def row(value: Mapping[str, object]) -> Mapping[str, object]:
        data = {k: v for k, v in value.items() if k != namespace}
        coerced = dict(mapping(coerce_input(layout_for_row, data), "input object"))
        if namespace in value:
            meta_value = mapping(value[namespace], "object metadata input")
            coerced[namespace] = coerce_input(object_layout, meta_value)
        elif object_layout:
            coerce_input(object_layout, None)
        return coerced

    layout_for_row = LayoutSpec("hash", None, layout.parameters, layout.raw)
    if layout.layout in ("object_list", "hash_list"):
        if params is None:
            return []
        if not isinstance(params, (list, tuple)):
            raise ValidationError("input layout requires a list of objects")
        return [row(mapping(v, "input row")) for v in params]
    return row(mapping(params or {}, "input"))


def build_request(
    description: Description,
    context: CallContext,
    *,
    base_url: str,
    params: InputParams | None = None,
    meta: Mapping[str, object] | None = None,
) -> RequestSpec:
    # Validate the static endpoint before substituting user data. Encoded slashes
    # within a bound ID are data, and must not be interpreted as path separators.
    resolve_url(base_url, context.action.path, path_mode="descriptor")
    path = _bind(context)
    base = urlsplit(base_url)
    url = urlunsplit(
        (
            base.scheme,
            base.netloc,
            path,
            "",
            "",
        )
    )
    payload = _coerce_with_object_meta(description, context, params)
    body: object = {}
    layout = context.action.input
    if layout:
        body = {layout.namespace: payload} if layout.namespace else payload
    if meta is not None:
        scope = context.action.meta.get("global")
        meta_layout = (
            parse_layout(scope.get("input")) if isinstance(scope, Mapping) else None
        )
        coerced_meta = coerce_input(meta_layout, meta)
        if not isinstance(body, Mapping):
            raise ValidationError(
                "list input requires a namespace to carry global metadata"
            )
        if description.meta_namespace in body:
            raise ProtocolError("metadata namespace collides with input")
        body = {**body, description.meta_namespace: coerced_meta}
    else:
        scope = context.action.meta.get("global")
        if isinstance(scope, Mapping) and scope.get("input") is not None:
            coerce_input(parse_layout(scope["input"]), None)
    headers = {"Accept": "application/json"}
    method = context.action.method
    if method in ("POST", "PUT", "DELETE"):
        if not isinstance(body, Mapping):
            raise ValidationError(
                "JSON action input requires an object root and a namespace for lists"
            )
        headers["Content-Type"] = "application/json"
        try:
            content = json.dumps(
                body, ensure_ascii=False, allow_nan=False, separators=(",", ":")
            ).encode("utf-8")
        except (TypeError, ValueError, UnicodeError) as error:
            raise ValidationError("input is not valid UTF-8 JSON") from error
        return RequestSpec(method, url, (), headers, content)
    if method == "GET":
        if not isinstance(body, Mapping):
            raise ValidationError("GET list input requires a namespace")
        scope = context.action.meta.get("object")
        object_meta = (
            parse_layout(scope.get("input")) if isinstance(scope, Mapping) else None
        )
        _query_custom_input(
            layout,
            payload,
            layout.namespace if layout and layout.namespace else "input",
            object_meta=object_meta,
            meta_namespace=description.meta_namespace,
        )
        scope = context.action.meta.get("global")
        if meta is not None and isinstance(scope, Mapping):
            _query_custom_input(
                parse_layout(scope.get("input")),
                mapping(body[description.meta_namespace], "global metadata"),
                description.meta_namespace,
            )
        pairs = []
        wrappers = set()
        if layout and layout.namespace:
            wrappers.add(layout.namespace)
        if meta is not None:
            wrappers.add(description.meta_namespace)
        if object_meta and isinstance(payload, Mapping):
            wrappers.add(
                f"{layout.namespace}[{description.meta_namespace}]"
                if layout and layout.namespace
                else description.meta_namespace
            )
        for name, value in body.items():
            _query_component(name, name)
            input_wrapper = layout is not None and name == layout.namespace
            if input_wrapper and params is None and value == []:
                continue  # Missing list input is omitted; explicit [] must fail.
            pairs.extend(
                _query_value(
                    value,
                    name,
                    empty_wrappers=frozenset(wrappers),
                )
            )
        query = tuple(pairs)
        return RequestSpec(method, url, query, headers, None)
    raise ProtocolError(f"unsupported action method: {method}")
