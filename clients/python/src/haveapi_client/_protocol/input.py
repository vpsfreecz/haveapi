"""Strict typed inputs from doc/typed-input-validation.md."""

from __future__ import annotations

import math
import re
from collections.abc import Mapping, Sequence
from datetime import date, datetime

from ..exceptions import ValidationError
from .models import InputObject, InputParams, LayoutSpec, ParameterSpec

_INTEGER = re.compile(r"[+-]?[0-9]+\Z")
_FLOAT = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\Z")
_DATETIME = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}"
    r"(?:T[0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]+)?)?"
    r"(?:Z|[+-][0-9]{2}:?[0-9]{2}))?\Z"
)


def json_value(value: object) -> object:
    """Copy only finite JSON values; never stringify unknown objects."""
    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float) and math.isfinite(value):
        return value
    if isinstance(value, Mapping) and all(isinstance(k, str) for k in value):
        return {k: json_value(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(v) for v in value]
    raise ValueError("not a finite JSON value")


def _coerce(spec: ParameterSpec, value: object) -> object:
    if value is None or (
        spec.nullable and isinstance(value, str) and not value.strip()
    ):
        if spec.nullable and not spec.required:
            return None
        raise ValueError("cannot be null")
    kind = spec.type
    if kind == "Integer":
        if type(value) is int:
            return value
        if isinstance(value, float) and math.isfinite(value) and value.is_integer():
            return int(value)
        if isinstance(value, str) and _INTEGER.fullmatch(value.strip()):
            return int(value.strip(), 10)
        raise ValueError("not a valid integer")
    if kind == "Float":
        if type(value) in (int, float) or (
            isinstance(value, str) and _FLOAT.fullmatch(value.strip())
        ):
            try:
                number = float(value)  # type: ignore[arg-type]
                if math.isfinite(number):
                    return number
            except (ValueError, OverflowError):
                pass
        raise ValueError("not a valid float")
    if kind == "Boolean":
        if isinstance(value, bool):
            return value
        if type(value) is int and value in (0, 1):
            return bool(value)
        if isinstance(value, str):
            token = value.strip().lower()
            if token in ("true", "t", "yes", "y", "1"):
                return True
            if token in ("false", "f", "no", "n", "0"):
                return False
        raise ValueError("not a valid boolean")
    if kind in ("String", "Text"):
        if isinstance(value, str):
            return value
        if isinstance(value, bool):
            return "true" if value else "false"
        if type(value) is int or isinstance(value, float) and math.isfinite(value):
            return str(value)
        raise ValueError("not a valid string")
    if kind == "Resource":
        if type(value) is int and value >= 0:
            return value
        if isinstance(value, str) and re.fullmatch(r"[0-9]+", value.strip()):
            return int(value.strip())
        raise ValueError("not a valid resource ID")
    if kind == "Datetime":
        if isinstance(value, datetime):
            if value.tzinfo is None or value.utcoffset() is None:
                raise ValueError("not in ISO 8601 format")
            value = value.isoformat()
        elif isinstance(value, date):
            value = value.isoformat()
        if isinstance(value, str) and _DATETIME.fullmatch(value):
            try:
                if "T" in value:
                    # fromisoformat validates dates and clock/offset components.
                    datetime.fromisoformat(value)
                    offset = re.search(r"[+-]([0-9]{2}):?([0-9]{2})$", value)
                    if offset and (int(offset[1]) > 23 or int(offset[2]) > 59):
                        raise ValueError("invalid offset")
                else:
                    date.fromisoformat(value)
                return value
            except ValueError:
                pass
        raise ValueError("not in ISO 8601 format")
    if kind == "Custom":
        return json_value(value)
    raise ValueError(f"unsupported input parameter type: {kind}")


def _coerce_object(layout: LayoutSpec, params: InputObject) -> InputObject:
    if not all(isinstance(k, str) for k in params):
        raise ValidationError("input keys must be strings")
    errors: dict[str, object] = {
        k: ["unknown parameter"] for k in params if k not in layout.parameters
    }
    result = {}
    for name, spec in layout.parameters.items():
        if name not in params:
            if spec.required:
                errors[name] = ["required parameter is missing"]
            continue
        try:
            result[name] = _coerce(spec, params[name])
        except ValueError as error:
            errors[name] = [str(error)]
    if errors:
        raise ValidationError("input parameters are not valid", errors=errors)
    return result


def coerce_input(layout: LayoutSpec | None, params: InputParams | None) -> InputParams:
    if layout is None:
        if params:
            raise ValidationError("action does not accept input parameters")
        return {}
    is_list = layout.layout in ("object_list", "hash_list")
    if params is None:
        params = [] if is_list else {}
    if is_list:
        if not isinstance(params, Sequence) or isinstance(params, (str, bytes)):
            raise ValidationError("input layout requires a list of objects")
        result = []
        errors: dict[str, object] = {}
        for index, row in enumerate(params):
            if not isinstance(row, Mapping):
                errors[str(index)] = ["input row must be an object"]
                continue
            try:
                result.append(_coerce_object(layout, row))
            except ValidationError as error:
                errors[str(index)] = error.errors
        if errors:
            raise ValidationError("input parameters are not valid", errors=errors)
        return result
    if not isinstance(params, Mapping):
        raise ValidationError("input layout requires an object")
    return _coerce_object(layout, params)
