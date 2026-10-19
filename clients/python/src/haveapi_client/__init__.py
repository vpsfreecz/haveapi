"""Dynamic clients for self-describing HaveAPI APIs."""

from importlib.metadata import version

from ._auth import (
    AsyncAuthenticationChallenge,
    Authenticated,
    AuthenticationChallenge,
    BasicAuth,
    OAuth2Auth,
    TokenAuth,
)
from ._protocol import RequestOptions
from .async_client import AsyncClient
from .client import Client
from .exceptions import (
    ActionError,
    AuthenticationError,
    HaveAPIError,
    NotConnectedError,
    OperationFailedError,
    OperationTimeoutError,
    PaginationError,
    ProtocolError,
    StaleDescriptionError,
    TransportError,
    ValidationError,
)
from .operations import AsyncOperation, Operation
from .pagination import IdCursor
from .response import ResourceObject, Response

__version__ = version("haveapi-client")

__all__ = [
    "ActionError",
    "AsyncAuthenticationChallenge",
    "AsyncClient",
    "AsyncOperation",
    "Authenticated",
    "AuthenticationChallenge",
    "AuthenticationError",
    "BasicAuth",
    "Client",
    "HaveAPIError",
    "IdCursor",
    "NotConnectedError",
    "OAuth2Auth",
    "Operation",
    "OperationFailedError",
    "OperationTimeoutError",
    "PaginationError",
    "ProtocolError",
    "RequestOptions",
    "ResourceObject",
    "Response",
    "StaleDescriptionError",
    "TokenAuth",
    "TransportError",
    "ValidationError",
    "__version__",
]
