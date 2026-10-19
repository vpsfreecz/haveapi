"""Validate response envelopes independently of HTTP transport behavior."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import cast

from ..exceptions import ActionError, AuthenticationError, ProtocolError
from .description import mapping
from .models import ActionSpec, DecodedResponse, Description, WireResponse


def _invalid_constant(value: str) -> None:
    raise ValueError(f"nonfinite JSON constant: {value}")


def decode_envelope(response: WireResponse) -> Mapping[str, object]:
    try:
        body = json.loads(response.content, parse_constant=_invalid_constant)
    except (ValueError, UnicodeError) as error:
        raise ProtocolError(
            "response is not valid JSON", status_code=response.status_code
        ) from error
    if not isinstance(body, dict) or not isinstance(body.get("status"), bool):
        raise ProtocolError(
            "invalid response envelope", status_code=response.status_code
        )
    envelope = cast(Mapping[str, object], body)
    message = body.get("message")
    errors = body.get("errors")
    if (
        message is not None
        and not isinstance(message, str)
        or errors is not None
        and not isinstance(errors, dict)
    ):
        raise ProtocolError(
            "invalid error context in response envelope",
            status_code=response.status_code,
        )
    if body["status"] is True and "response" not in body:
        raise ProtocolError(
            "response envelope has no response member", status_code=response.status_code
        )
    if body["status"] is False or not 200 <= response.status_code < 300:
        cls = AuthenticationError if response.status_code == 401 else ActionError
        raise cls(
            message or f"action failed (HTTP {response.status_code})",
            status_code=response.status_code,
            errors=errors,
            envelope=envelope,
        )
    return envelope


def decode_response(
    description: Description, action: ActionSpec, response: WireResponse
) -> DecodedResponse:
    envelope = decode_envelope(response)
    payload = envelope["response"]
    namespace = description.meta_namespace
    meta: Mapping[str, object] = {}
    if isinstance(payload, Mapping) and namespace in payload:
        try:
            meta = mapping(payload[namespace], "global response metadata")
        except ProtocolError as error:
            raise ProtocolError(
                error.message, status_code=response.status_code
            ) from error
    output = action.output
    data = None
    if output:
        if output.namespace:
            if not isinstance(payload, Mapping) or output.namespace not in payload:
                raise ProtocolError(
                    "missing response output namespace",
                    status_code=response.status_code,
                )
            data = payload[output.namespace]
        else:
            data = (
                {k: v for k, v in payload.items() if k != namespace}
                if isinstance(payload, Mapping)
                else payload
            )
        is_list = output.layout in ("object_list", "hash_list")
        valid = (
            isinstance(data, list) and all(isinstance(v, dict) for v in data)
            if is_list
            else isinstance(data, dict)
        )
        if not valid:
            raise ProtocolError(
                "invalid response output layout", status_code=response.status_code
            )
    return DecodedResponse(data, meta, envelope, response.status_code, response.headers)
