"""Parse HaveAPI descriptions without rewriting server-owned names."""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import cast

from ..exceptions import ProtocolError
from .models import (
    ActionSpec,
    Description,
    LayoutSpec,
    ParameterSpec,
    ResourceSpec,
    frozen_mapping,
)

PATH_PARAMETER = re.compile(r"\{([a-zA-Z0-9_-]+)\}")
LAYOUTS = frozenset(("object", "object_list", "hash", "hash_list"))


def mapping(value: object, label: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping) or not all(isinstance(k, str) for k in value):
        raise ProtocolError(f"{label} must be an object with string keys")
    return cast(Mapping[str, object], value)


def _string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ProtocolError(f"{label} must be a nonempty string")
    return value


def _boolean(raw: Mapping[str, object], name: str) -> bool:
    value = raw.get(name, False)
    if value is None:
        return False
    if not isinstance(value, bool):
        raise ProtocolError(f"{name} must be boolean")
    return value


def parse_layout(value: object) -> LayoutSpec | None:
    if value is None:
        return None
    raw = mapping(value, "layout")
    layout = _string(raw.get("layout"), "layout type")
    if layout not in LAYOUTS:
        raise ProtocolError(f"unsupported layout: {layout}")
    namespace = raw.get("namespace")
    if namespace is False or namespace is None:
        namespace = None
    elif not isinstance(namespace, str) or not namespace:
        raise ProtocolError("namespace must be a nonempty string or false")
    parameters = {}
    for name, entry in mapping(raw.get("parameters", {}), "parameters").items():
        spec = mapping(entry, f"parameter {name}")
        parameters[name] = ParameterSpec(
            name,
            _string(spec.get("type"), "parameter type"),
            _boolean(spec, "required"),
            _boolean(spec, "nullable"),
            spec,
        )
    return LayoutSpec(layout, namespace, parameters, raw)


def _action(name: str, value: object, resource_path: tuple[str, ...]) -> ActionSpec:
    raw = mapping(value, f"action {name}")
    method = _string(raw.get("method"), "action method").upper()
    if method not in {"GET", "DELETE", "POST", "PUT"}:
        raise ProtocolError(f"unsupported action method: {method}")
    path = _string(raw.get("path"), "action path")
    unmatched = PATH_PARAMETER.sub("", path)
    if "{" in unmatched or "}" in unmatched:
        raise ProtocolError("invalid action path template")
    aliases = raw.get("aliases", ())
    if not isinstance(aliases, (list, tuple)) or not all(
        isinstance(v, str) for v in aliases
    ):
        raise ProtocolError("action aliases must be an array of strings")
    meta = mapping(raw.get("meta") or {}, "action metadata")
    for scope in ("global", "object"):
        if meta.get(scope) is not None:
            scope_raw = mapping(meta[scope], f"{scope} metadata")
            parse_layout(scope_raw.get("input"))
            parse_layout(scope_raw.get("output"))
    return ActionSpec(
        name,
        resource_path,
        method,
        path,
        tuple(PATH_PARAMETER.findall(path)),
        tuple(cast(list[str], aliases)),
        parse_layout(raw.get("input")),
        parse_layout(raw.get("output")),
        meta,
        _boolean(raw, "blocking"),
        _boolean(raw, "auth"),
        raw,
    )


def parse_resources(
    raw: Mapping[str, object], *, parent_path: tuple[str, ...] = ()
) -> Mapping[str, ResourceSpec]:
    resources = {}
    for name, value in mapping(raw, "resources").items():
        spec = mapping(value, f"resource {name}")
        path = (*parent_path, name)
        actions = {
            action_name: _action(action_name, entry, path)
            for action_name, entry in mapping(
                spec.get("actions", {}), "actions"
            ).items()
        }
        resources[name] = ResourceSpec(
            name,
            path,
            parse_resources(
                mapping(spec.get("resources", {}), "nested resources"), parent_path=path
            ),
            actions,
            spec,
        )
    return frozen_mapping(resources)


def parse_description(
    envelope: Mapping[str, object], *, api_version: str | None = None
) -> Description:
    raw = mapping(envelope, "description envelope")
    if raw.get("status") is not True:
        raise ProtocolError("description envelope must indicate success")
    protocol = raw.get("version")
    if not isinstance(protocol, str) or not re.fullmatch(r"2\.[0-9]+", protocol):
        raise ProtocolError(
            "unsupported or missing protocol version (expected major 2)"
        )
    body = mapping(raw.get("response"), "API description")
    resources = parse_resources(mapping(body.get("resources"), "resources"))
    authentication = {
        name: mapping(value, f"authentication {name}")
        for name, value in mapping(
            body.get("authentication", {}), "authentication"
        ).items()
    }
    meta = mapping(body.get("meta", {}), "metadata description")
    namespace = _string(meta.get("namespace", "_meta"), "metadata namespace")
    return Description(
        protocol, api_version, resources, authentication, namespace, body
    )


def lookup_resource(description: Description, path: tuple[str, ...]) -> ResourceSpec:
    if not path:
        raise KeyError("resource path cannot be empty")
    resources = description.resources
    for name in path:
        resource = resources[name]
        resources = resource.resources
    return resource


def lookup_action(
    description: Description, resource_path: tuple[str, ...], name: str
) -> ActionSpec:
    resource = lookup_resource(description, resource_path)
    if name in resource.actions:
        return resource.actions[name]
    matches = [a for a in resource.actions.values() if name in a.aliases]
    if len(matches) != 1:
        reason = "ambiguous" if matches else "unknown"
        raise KeyError(f"{reason} action or alias: {name}")
    return matches[0]
