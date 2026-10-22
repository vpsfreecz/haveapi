# HaveAPI Python client

`haveapi-client` discovers resources, actions and parameter types from any
HaveAPI API using protocol 2.x. It provides synchronous and asynchronous clients
with the same dynamic interface. Python 3.11 or newer is required.

[vpsAdmin](https://github.com/vpsfreecz/vpsadmin) is the control panel used by
vpsFree.cz to manage virtual private servers (VPSes). It is HaveAPI's main user,
so the examples in this README and the `examples/` directory use its API.

Install the package with `uv add haveapi-client` or `pip install haveapi-client`
once a Python release is available. To try a checkout before publication, run
`uv add /path/to/haveapi/clients/python` in your application.

## Read a page of VPSes

The examples use an existing vpsAdmin API token. Set `VPSADMIN_URL` to the API
base URL and `VPSADMIN_TOKEN` to your token. Keep credentials out of source files.

```python
import os

from haveapi_client import Client, TokenAuth

with Client(
    os.environ["VPSADMIN_URL"], auth=TokenAuth(os.environ["VPSADMIN_TOKEN"])
) as api:
    result = api.vps.list.call(params={"limit": 100}, meta={"count": True})
    for vps in result.data:
        print(vps["id"], vps["hostname"])
    print(result.meta.get("total_count"))
```

Use `AsyncClient` with `async with` and await action calls for async applications.
It works with asyncio and Trio. Complete runnable examples are in
[`examples/list_vps.py`](examples/list_vps.py) and
[`examples/list_vps_async.py`](examples/list_vps_async.py).

## Discovery and calls

Constructing a client and inspecting resource or action properties sends no
requests. Call `connect()` explicitly or enter the client context to fetch its
description. An authenticated connection refreshes discovery with the selected
identity, so available actions and parameters reflect server authorization.
The server still authorizes every request.

The base URL includes the API mount, for example `https://api.example/mount/`.
Select the API version with the client's `version` argument. Discovery uses that
mount and version; described action paths already contain their routing prefix
and resolve from the origin. The client preserves the server's ordinary,
authentication and action-state routes without repeating the mount or adding
a version to a global authentication route.

Action destinations must remain within the configured origin and mount before
credentials are attached. Applications that fabricate or cache API-relative
action descriptions for a mounted API must refresh them from the server's
OPTIONS description. Root-mounted APIs keep the same URLs.

`api.vps.list(limit=10)` is shorthand for
`api.vps.list.call(params={"limit": 10})`. Use `.call()` to pass action metadata,
explicit path parameters or per-request `RequestOptions`. Input values are
validated and encoded from the description. Omitted parameters and explicit
`None` have different meanings; `None` is accepted only where advertised.

POST, PUT and DELETE send JSON input and metadata. The Ruby server requires
the JSON root to be an object: list input needs a described namespace around
it. An unnamespaced list body is rejected locally. JSON retains empty
containers, sparse object rows, and finite numbers, booleans and nulls in
Custom values.

GET uses Rack bracket-query encoding. It accepts only shapes that can be
represented without changing their meaning:

- Described scalar values use their normal type conversion, including the
  empty query value for a permitted nullable scalar.
- Nonempty mappings can nest. Every key component, including described
  namespaces and parameter names, must be nonempty and contain no `[` or `]`.
- Nonempty arrays of strings retain their order. Arrays of flat objects must
  have the same nonempty key set in every row, with no container-valued fields.
  The client emits each row's keys in the same order. Described row fields use
  their declared types; Custom row fields must contain strings.
- Nested Custom values may contain strings, mappings and these permitted
  arrays. Nested numbers, booleans and nulls are rejected because a query
  cannot preserve their JSON types. A nullable top-level Custom value follows
  the normal nullable-scalar rule.
- Sparse rows, empty rows, nested arrays, explicit empty lists or mappings,
  and object arrays with container-valued fields are rejected. Omitted input
  remains omitted; structural input or metadata wrappers with no supplied
  fields do not require a query pair.

The same GET restrictions apply to metadata. Invalid shapes raise
`ValidationError` before an action request is sent. The client follows the
action's described method; it does not replace GET with JSON. Only the literal
`Custom` parameter type accepts arbitrary finite JSON values. Unknown parameter
type names are rejected rather than treated as Custom.

For names that collide with Python methods or keywords, use exact-name maps:
`api.resources["vps"].actions["index"]`. Indexing a resource binds one path
argument, such as `api.vps[vps_id].show()`. Follow the discovered hierarchy for
nested resources: `api.parent[parent_id].child.list()` applies when that API
describes a child resource under its parent. In vpsAdmin, network interfaces
are top-level: use `api.network_interface.list(vps=vps_id)`.

An action returns `Response`: `.data` is a finite result, `.meta` contains action
metadata, and `.status_code`, `.headers` and `.envelope` expose response context.
Returned objects are read-only mappings with optional attribute access to
fields. Mapping access remains reliable when a field name collides with a method.
Association handles can be inspected without fetching them; call `.fetch()`
explicitly to retrieve an association. Refreshing discovery or changing
authentication invalidates previously obtained resource and object handles.

## Authentication

Use `BasicAuth(username, password)`, `TokenAuth(token)` or
`OAuth2Auth(access_token)` for an existing credential. OAuth2Auth sends a bearer
token; browser authorization and token refresh are outside this package.

For password-based token login, call
`api.begin_token_login({"user": username, "password": password, ...})` with
fields accepted by that API. The result is `Authenticated` or an
`AuthenticationChallenge`. Read a challenge's `.next_action` and `.input`, then
call `.submit({...})` with the required fields. Continue until authenticated;
this supports API-specific chains such as TOTP followed by a password reset.
`AsyncClient` returns `AsyncAuthenticationChallenge`, whose submit is awaited.
The continuation token is kept by the challenge and cannot be overridden.

`renew_token()` and `revoke_token()` use the provider's advertised actions.
`logout()` clears local authentication and rediscovers the public API. Closing a
client does not revoke its server token. Credentials are kept in memory; the
package does not write a credential cache.

## Pagination and operations

Normal action calls fetch one page. Use `action.iter_pages(...)` or
`action.iter_all(...)` for explicit iteration. Async clients return async
iterators. Supply a cursor strategy that matches the endpoint's ordering:

```python
from haveapi_client import IdCursor

for vps in api.vps.list.iter_all(strategy=IdCursor(direction="asc"), page_size=100):
    print(vps["id"])
```

`IdCursor` requires integer IDs in the requested monotonic order and rejects a
repeated or reversed cursor. The endpoint must advertise `limit` and the cursor
parameter. HaveAPI pagination metadata alone does not promise this ordering;
select the strategy from the API's documented behavior.

When a response includes an operation, use `response.operation.show()`,
`.wait(timeout=300, interval=1)` or `.cancel()`. Await these methods on an async
operation. Waiting checks the described action-state resource and raises
`OperationFailedError` for failure or `OperationTimeoutError` at the deadline.
Timeout and coroutine cancellation do not cancel the server operation. Explicit
cancel requires advertised cancellation support.

Async waits enforce the overall deadline. A synchronous wait checks its budget
between requests and bounds each HTTP phase by the remaining time; an in-flight
synchronous request can finish after the overall deadline.

## Errors and connection ownership

Catch `HaveAPIError` for client errors, or its more specific `TransportError`,
`ProtocolError`, `AuthenticationError`, `ValidationError` and `ActionError`
subclasses. Errors provide status and structured details when available. Treat
response payloads and diagnostics as potentially private application data.

The default HTTP timeout is 30 seconds and can be overridden per request with
`RequestOptions(timeout=...)`. Requests are not retried or redirected. Clients
use independent request headers and bodies; authentication changes are rejected
while requests are active. Injected HTTPX clients remain caller-owned and must
be closed by the caller. Their default authentication, headers and cookies are
not inherited by HaveAPI requests.

See [CONTRIBUTING.md](CONTRIBUTING.md) for checks and packaging, and the shared
[release procedure](../../doc/agent-instructions/releases.md) for publication.
