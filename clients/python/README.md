# HaveAPI Python client

`haveapi-client` discovers resources, actions and parameter types from a
HaveAPI server using protocol 2.x. It provides synchronous and asynchronous clients
with the same dynamic interface. Python 3.11 or newer is required.

[vpsAdmin](https://github.com/vpsfreecz/vpsadmin) is the control panel used by
vpsFree.cz to manage virtual private servers (VPSes). It is HaveAPI's main user,
so the examples in this README and the `examples/` directory use its API.

## Installation

Add the package from PyPI to your project with uv:

```sh
uv add haveapi-client
```

Or install it with pip in your application's Python environment:

```sh
python3 -m pip install haveapi-client
```

## Synchronous client

Set `VPSADMIN_TOKEN` to an existing vpsAdmin API token. Keep credentials out of
source files. This example reads one page of VPSes:

```python
import os

from haveapi_client import Client, TokenAuth

with Client(
    "https://api.vpsfree.cz", auth=TokenAuth(os.environ["VPSADMIN_TOKEN"])
) as api:
    result = api.vps.list(limit=10)
    for vps in result.data:
        print(vps["id"], vps["hostname"])
```

Entering `with` discovers the API and the actions available to your token.
These examples use the server's default API version. Pass the API root to the
constructor, including any mount such as `https://api.example/mount/`, without
appending a version. To select a particular version, use the optional `version`
constructor argument.

## Asynchronous client

`AsyncClient` has the same resource/action interface. Use `async with` and await
action calls. This asyncio example reads the same page:

```python
import asyncio
import os

from haveapi_client import AsyncClient, TokenAuth


async def main():
    async with AsyncClient(
        "https://api.vpsfree.cz", auth=TokenAuth(os.environ["VPSADMIN_TOKEN"])
    ) as api:
        result = await api.vps.list(limit=10)
        for vps in result.data:
            print(vps["id"], vps["hostname"])


asyncio.run(main())
```

The async client also works with Trio. The runnable scripts in
[`examples/list_vps.py`](examples/list_vps.py) and
[`examples/list_vps_async.py`](examples/list_vps_async.py) accept the API URL and
token from environment variables.

## Authentication

Pass `TokenAuth(token)`, `BasicAuth(username, password)` or
`OAuth2Auth(access_token)` as the constructor's `auth` argument. Omit `auth` for
public resources. OAuth2Auth sends an existing bearer token; browser
authorization and token refresh are outside this package.

Password-based token login, including multi-step challenges such as TOTP, uses
`begin_token_login()`. See [token login](docs/reference.md#token-login) for the
continuation flow, token renewal and revocation. Closing a client does not revoke
its server token. The package keeps credentials in memory and writes no
credential cache.

## Resources, actions and results

Resources and actions come from the API description. Index a resource to bind
its ID. Inside a connected synchronous client context, with `vps_id` set to an
accessible VPS ID:

```python
detail = api.vps[vps_id].show()
print(detail.data["hostname"])

interfaces = api.network_interface.list(vps=vps_id)
for interface in interfaces.data:
    print(interface["id"])
```

vpsAdmin exposes network interfaces at the top level. Follow the discovered
hierarchy for other APIs. Use exact-name maps such as
`api.resources["vps"].actions["index"]` for names that collide with Python methods
or keywords. Resource and action lookup sends no requests.

`api.vps.list(limit=10)` is shorthand for
`api.vps.list.call(params={"limit": 10})`. Use `.call()` for action metadata,
explicit path parameters or per-request options. For example, vpsAdmin's count
metadata requests the total number of matching VPSes:

```python
page = api.vps.list.call(params={"limit": 10}, meta={"count": True})
print(page.meta["total_count"])
for vps in page.data:
    print(vps["id"], vps["hostname"])
```

With `AsyncClient`, await the same calls, for example
`detail = await api.vps[vps_id].show()` and
`page = await api.vps.list.call(params={"limit": 10}, meta={"count": True})`.

Each action returns a `Response`: `.data` holds the result and `.meta` holds
action metadata. Returned objects are read-only mappings; access fields with
expressions such as `vps["hostname"]`. Associations are not fetched automatically: call an
association's `.fetch()` explicitly, awaiting it with the async client.

Input is validated against the description. Omitting a parameter differs from
passing `None`; `None` is accepted only where advertised. GET has stricter shape
limits than JSON requests. See the [input encoding reference](docs/reference.md#input-encoding)
for those limits.

## Pagination and operations

Normal list calls fetch one page. Use `action.iter_pages(...)` or
`action.iter_all(...)` for explicit iteration. Async clients return async
iterators, consumed with `async for`. Inside a connected synchronous client
context, supply a cursor strategy that matches the endpoint's ordering:

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
operation. For an existing synchronous action result:

```python
if result.operation is not None:
    final_state = result.operation.wait(timeout=300, interval=1)
    print(final_state.data)
```

Waiting checks the described action-state resource and raises
`OperationFailedError` for failure or `OperationTimeoutError` at the deadline.
Timeout and coroutine cancellation do not cancel the server operation. Explicit
cancel requires advertised cancellation support.

See [operation deadlines](docs/reference.md#operation-deadlines) for the
difference between synchronous and asynchronous wait timeouts.

## Errors and timeouts

Catch `HaveAPIError` for client errors, or its more specific `TransportError`,
`ProtocolError`, `AuthenticationError`, `ValidationError` and `ActionError`
subclasses. Errors provide status and structured details when available. Treat
response payloads and diagnostics as potentially private application data.

The default HTTP timeout is 30 seconds and can be overridden per request with
`RequestOptions(timeout=...)` through `.call(options=...)`. Requests are not
retried or redirected.

## Reference and development

See the [runtime reference](docs/reference.md) for discovery, URL resolution,
encoding, response fields and connection ownership.

For development against a local HaveAPI checkout, run
`uv add /path/to/haveapi/clients/python` in your application. See
[CONTRIBUTING.md](CONTRIBUTING.md) for checks and packaging, and the shared
[release procedure](../../doc/agent-instructions/releases.md) for publication.
