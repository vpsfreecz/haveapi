# Async resources and binding

The package exports `AsyncClient` for Promise-based calls and `CallbackClient`
for callbacks. `Client` remains a supported alias of `CallbackClient`.
Dynamic async calls return `{ value, response }`; `response`
contains `data`, `meta`, the raw `envelope` and `httpStatus`. A successful reply
can be an acceptance receipt for a server job. Use `waitForCompletion` separately
when the application needs its final outcome.

```js
const api = new HaveAPI.AsyncClient('https://api.example');
await api.setup();
const { value: widgets } = await api.resource('widget').action('list')({
  params: { limit: 10 }, meta: { includes: ['owner'] }
});
const widget = widgets.first();
const owner = await widget.loadAssociation('owner');
```

Resource selectors can curry IDs, and actions also accept IDs followed by an
options object (`params`, `meta`, `headers`, `signal`, `timeoutMs`). They reject
callback invocation forms. IDs, options and metadata are captured per call;
concurrent calls do not share a prepared path. Returned objects use the server's
`path_params` metadata for their bound identity. The client does not infer IDs
from arbitrary payload fields. A response without identity metadata remains
readable; an ID-dependent action needs an explicit binding before it can send.

Instance getters, list indexing/iteration and `resource.new(attributes)` are
local. Property access never fetches an association. `loadAssociation` returns
`{ value, response }`: a prefetched/cached result has `response: null`; a network
load retains its actual response. Failed loads reject without publishing a
partially loaded object. Replacing an association value clears its local cache.

`save()` snapshots submitted attributes, waits for create/update, validates the
result, then publishes attributes, identity and action bindings together.
Local attributes may refer to other async resource instances. For a described
Resource input, actions and save extract the field named by `value_id` (default
`id`) from that instance or an own field of an association record before
capturing the scalar request value. Missing or invalid identifiers reject validation;
a custom `value_id` does not fall back to `id`. This conversion does not bind
the associated resource's action path. Other local data and request metadata
retain their normal snapshot behavior.

Updates retain an existing binding when the reply omits identity metadata;
explicit invalid metadata rejects. Singleton resources do not require IDs.
If a create's 2xx reply has a valid success envelope but lacks a usable payload,
namespace, metadata or required identity, save rejects with that response and an
`accepted-unbound` reason. That object blocks later saves to prevent a duplicate
create. Fetch the created resource before making further changes. The create
remains accepted on the server. Transport failures and responses without a
validated success envelope do not establish acceptance.

All async client/resource/action/instance/list objects have a noncallable `then`.
A described `then` name or a helper collision remains available through explicit
`resource(name)`, `action(name)` or instance `get(name)` lookup. API properties
stay nested in results. Async objects never expose callback-owned resource or
provider helpers.

A successful setup or authentication replacement invalidates older bound
objects for new network sends. In-flight calls retain the context captured when
sent and cannot replace the newer root registry. Local reads and
cached association access remain local. Obtain a fresh resource from the current
client before sending another request. Low-level `request()` uses the current
context and needs no resource description.

The resource unit checks are described in [test/README.md](test/README.md).
They use a context-bound fake transport, not a live API. The shared contract
suite selects both callback and async test adapters; real-server/browser checks
are separate verification steps and must not be inferred from unit results.
