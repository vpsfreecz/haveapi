# Async client requests and authentication

`HaveAPI.AsyncClient` and `HaveAPI.CallbackClient` are exported by one package.
`HaveAPI.Client` remains a supported alias of `CallbackClient`, including its
constructor, prototype and static helpers. Both callback names are also usable
as TypeScript instance types. The CommonJS entry and browser global remain
available:

```js
const HaveAPI = require('haveapi-client');

async function main() {
  const api = new HaveAPI.AsyncClient('https://api.example');
  await api.authenticate('token', {token: existingToken});
}

main().catch(console.error);
```

CommonJS callers use `await` inside an async function. They do not need a
TypeScript compiler or runtime loader.

The async client has independent authentication, language and resource state.
It rejects callback invocation forms. The callback client retains its callback
arguments, undefined returns, synchronous local exceptions and callback-free
calls; its operations do not start returning Promises.

## Path-based requests

`request<T>()` works before `setup()` and does not download an API description.
Use it when an application already knows its paths and payload types:

```ts
import {AsyncClient} from 'haveapi-client';

interface Widget {id: number; name: string}
const api = new AsyncClient('https://api.example', {language: 'en'});
const result = await api.request<Widget>({
  method: 'GET',
  path: '/v1/widgets/42',
  outputNamespace: 'widget',
  signal,
  timeoutMs: 10000,
  headers: currentAuthenticationHeaders()
});
console.log(result.data.name, result.meta, result.httpStatus);
```

Results have fixed `data`, `meta`, `envelope` and `httpStatus` fields. A type
argument describes the expected payload; it does not validate its application
fields at runtime. The client validates the response envelope and a selected
output namespace. Description-driven calls use the same request pipeline;
see [Async resources and binding](doc-async-resources.md) for their richer
`{value, response}` results, save behavior and explicit association loading.

With base `https://api.example/mount/`, a raw request path `/v2/widgets/42`
requests `https://api.example/mount/v2/widgets/42`. Described resource, token and
action-state paths are origin-root-relative: the advertised path
`/mount/v2/widgets/42` requests that exact route at the configured origin.
Discovery retains the configured mount and selected version. Global token routes
keep the server's advertised version choice. Neither path form triggers a guessed
mount/version prefix or a retry at another URL.

Request fields:

- `method` and `path` select the request. Paths are API-relative and retain a
  configured base path. Cross-origin paths and authority-changing paths reject
  before credentials are sent.
- `params` and `inputNamespace` select input parameters. GET and OPTIONS encode
  parameters in the query; other methods send JSON. An omitted or null input
  namespace sends parameters at the root. Null query values become empty
  strings; undefined values are omitted.
- `meta` uses `metaNamespace`, which defaults to the current description's
  namespace or `_meta` before setup. `outputNamespace` selects an own field of
  the response payload; omit it or use null to retain the root payload.
- `headers` override configured authentication and language headers for this
  request, with case-insensitive name matching. Header names and values are
  validated. Set the client's language before setup/authentication to load
  translated descriptions; changing it later does not reload descriptions.
- `signal` aborts a request locally, including when already aborted before
  dispatch. `timeoutMs`, when supplied, must be finite and positive. Request
  timers and abort listeners are removed after settlement.

The transport sends each request once. It does not refresh sessions, retry
reads or replay mutations. An application adapter supplies current credentials
and owns its refresh policy, session identity checks and any deliberate retry.
Aborting observation does not establish whether the server accepted a mutation.

## Setup and authentication

`setup(): Promise<void>` downloads and validates the selected description.
`authenticate(method, options): Promise<void>` can run before setup and refreshes
the authorized description before publishing credentials and resources.
`availableVersions()` reads the protocol's root version-list payload and returns
its `versions` and `default` fields. OPTIONS descriptions use the ordinary
protocol envelope, with their document directly under `response`.

Basic credentials, existing tokens, token acquisition and existing OAuth2 access
tokens are supported. Provider setup does not separately prove credential
validity; resource visibility and API replies still depend on the server.
Multi-step token authentication uses an input-returning handler:

```js
await api.authenticate('token', {
  user: 'member', password,
  onChallenge: async (action, parameters) => ({code: await askForCode(action)})
});
```

A missing or rejected challenge handler rejects authentication. Credentials and
partial MFA tokens are not published after a failed description refresh.
Automatic renewal, OAuth authorization-code/session management and a convenience
logout method are not included. Applications can invoke their explicit revoke
endpoint through the request API.

Setup and authentication changes are serialized. Each successful replacement
publishes a complete resource tree and invalidates earlier resource bindings for
future sends. A stale binding rejects with a protocol error whose `reason` is
`stale-binding`. Already dispatched requests can finish with their original
context and do not replace the current tree. Low-level requests use the current
context at dispatch and have no resource-schema binding. `useDescription()`
validates and installs a local snapshot synchronously; a pending lifecycle
result cannot overwrite a newer snapshot.

## Errors and server completion

Promise failures are `HaveAPI.AsyncError` instances. `kind` identifies
`validation`, `transport`, `protocol`, `authentication`, `api`, `action-failed`,
`timeout` or `aborted`. Available details include `httpStatus`, `response`,
`envelope`, parameter `errors`, action `state`, `reason` and `cause`. Unavailable
fields are absent. Aborted errors use the recognizable name `AbortError`.
HTTP failure and HaveAPI envelope failure are both checked; HTTP status remains
available independently of the envelope. Request credentials and headers are
not attached to errors.

Server `errors` can contain nested parameter maps with arrays of strings at
their leaves. `ApiErrors` describes this wire shape; local parameter validation
still produces a flat map of string arrays. The server's public `error!` method
forwards custom error maps through recursive localization, although standard
parameter validation produces flat errors. A valid nested rejection retains its
errors, envelope and response receipt as an `api` failure for both HTTP 200 and
error statuses. Scalar error leaves and invalid metadata remain protocol errors.

After validating the envelope, payload decoding errors retain a `response`
receipt. Its `data` is the raw `envelope.response`, or `undefined` if the payload
is missing. `meta` contains validated metadata or an empty object.

A successful blocking-action invocation returns its initial reply immediately.
Waiting for the server job is a separate operation:

```js
const started = await api.resource('widget').action('restart')(42);
const completed = await api.waitForCompletion(started, {
  timeoutMs: 120000,
  signal,
  onStateChange: state => console.log(state.progress.current)
});
```

The wait uses the action's blocking flag and its `action_state_id` receipt.
Nonblocking replies return with `state: null`. Blocking waits require a positive
overall timeout; this differs from a single server poll timeout. Failed terminal
execution rejects even if polling HTTP/envelope status succeeded. Poll failures,
malformed state, abort and timeout also reject, retaining the original receipt
and last available state. Progress state is data, without callback-era stop or
cancel methods. Server cancellation is an explicit action, and its own reply
may describe another blocking job. No local timeout or abort cancels a server
job. A wait makes requests using its receipt's binding; replacing that binding
can reject further polling as stale.

## Packaging, compatibility and verification

Both APIs are authored in TypeScript. The retained gulp command emits ES5
JavaScript and generated declarations under `dist/types`, then builds the same
UMD artifact for CommonJS, AMD and browser script tags. Type declarations do not
infer endpoint names downloaded at runtime; applications can supply endpoint
schemas or use the typed path API. Dynamic async-owned objects reserve a
noncallable `then`; explicit lookup keeps remote names accessible safely.

The new surface uses native Promise and AbortController/AbortSignal in current
browsers. Loading the bundle and using the callback client does not eagerly
require these async primitives. The package adds no engines restriction or
polyfill. Development checks use the repository's Nix Node environment; exact
browser verification belongs in release evidence, rather than a claim of
support inferred from ES5 syntax alone.

No server/protocol update, persisted-state conversion or coordinated deployment
is required. Callback and async consumers can coexist. Rollback reverts the
client dependency/bundle together with application calls that require the new
surface; it does not require a data rollback. Publishing remains a separate
release operation.
