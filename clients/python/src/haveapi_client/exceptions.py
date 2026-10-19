"""Public error categories with safe, inspectable protocol context."""

from __future__ import annotations

from collections.abc import Mapping
from types import MappingProxyType


def _redact(value: object) -> object:
    if isinstance(value, Mapping):
        return MappingProxyType(
            {
                str(k): (
                    "<redacted>"
                    if any(s in str(k).lower() for s in ("token", "password", "secret"))
                    else _redact(v)
                )
                for k, v in value.items()
            }
        )
    if isinstance(value, (list, tuple)):
        return tuple(_redact(v) for v in value)
    return value


class HaveAPIError(Exception):
    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        errors: Mapping[str, object] | None = None,
        envelope: Mapping[str, object] | None = None,
        operation_id: str | int | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.errors = MappingProxyType(dict(errors or {}))
        # Arbitrary protected parameter names cannot be inferred from an envelope.
        # Retain its diagnostic shape, but never expose a failed response payload.
        self.envelope = MappingProxyType(
            {
                k: "<redacted>" if k == "response" else _redact(v)
                for k, v in (envelope or {}).items()
            }
        )
        self.operation_id = operation_id


class ProtocolError(HaveAPIError):
    pass


class TransportError(HaveAPIError):
    pass


class AuthenticationError(HaveAPIError):
    pass


class ValidationError(HaveAPIError):
    pass


class ActionError(HaveAPIError):
    pass


class NotConnectedError(HaveAPIError):
    pass


class StaleDescriptionError(HaveAPIError):
    pass


class PaginationError(HaveAPIError):
    pass


class OperationFailedError(HaveAPIError):
    pass


class OperationTimeoutError(HaveAPIError):
    pass
