# HaveAPI client for JavaScript and TypeScript

This package discovers a HaveAPI server's resources and actions at runtime.
It provides two interfaces, both usable from JavaScript and TypeScript:

| Interface | Constructor | Setup and authentication | Action result |
| --- | --- | --- | --- |
| Callbacks | `CallbackClient` | Callback receives `(client, ready)` | Callback receives `(client, reply)`; check `reply.isOk()` |
| Promises / async-await | `AsyncClient` | Await `setup()` or `authenticate()` | Await an action to receive `{ value, response }`; failures reject |

`Client` remains an alias of `CallbackClient`.

## Installation

```sh
npm install haveapi-client
```

The package includes compiled JavaScript and declarations for its public
TypeScript interface. You can use it without building the library.

For browser script tags, copy `dist/haveapi-client.js` into your project and load
it before your application:

```html
<script src="haveapi-client.js"></script>
```

The constructors are then available as `HaveAPI.CallbackClient` and
`HaveAPI.AsyncClient`. Node.js examples below use the CommonJS package entry.

## Quickstarts

Give either client the API root, including any mount path, without appending an
API version. Omitting the `version` option selects the server's default version.
`setup()` downloads the public API description. `authenticate()` can run first
and also loads the authorized description, so these examples need no separate
setup call.

The four examples list VPSes from vpsAdmin using an existing token in the
`VPSADMIN_TOKEN` environment variable. Resource names, actions, input fields and
visibility depend on the server's description and your permissions.

### JavaScript with callbacks

```js
const { CallbackClient } = require('haveapi-client');

const token = process.env.VPSADMIN_TOKEN;
if (!token) throw new Error('Set VPSADMIN_TOKEN to an existing API token');

const api = new CallbackClient('https://api.vpsfree.cz');
api.authenticate('token', { token }, (client, ready) => {
  if (!ready) {
    console.error('Authentication or API discovery failed');
    return;
  }

  client.vps.list({ limit: 10 }, (owner, vpses) => {
    if (!vpses.isOk()) {
      console.error('Unable to list VPSes');
      return;
    }
    vpses.each(vps => console.log(vps.id, vps.hostname));
  });
});
```

Setup and authentication callbacks receive a boolean status. Action callbacks
receive a response, resource instance or resource list, according to the action's
output layout. These callbacks use `(client, result)` rather than Node's
error-first convention. Callback operations do not return Promises; local
invocation errors can throw synchronously.

### JavaScript with async-await

```js
const { AsyncClient } = require('haveapi-client');

async function main() {
  const token = process.env.VPSADMIN_TOKEN;
  if (!token) throw new Error('Set VPSADMIN_TOKEN to an existing API token');

  const api = new AsyncClient('https://api.vpsfree.cz');
  await api.authenticate('token', { token });
  const { value: vpses } = await api.vps.list({
    params: { limit: 10 }
  });
  vpses.each(vps => console.log(vps.get('id'), vps.get('hostname')));
}

main().catch(console.error);
```

`value` contains the materialized action output: an `AsyncResourceInstance` for
`object`, an `AsyncResourceList` for `object_list`, or ordinary data for other
layouts. `response` contains `data`, `meta`, `envelope` and `httpStatus`.
Transport, protocol, authentication, validation and API failures reject the
Promise with an `AsyncError`; there is no callback status to inspect.

### TypeScript with callbacks

The declarations describe the library interface. Endpoint names downloaded at
runtime are not statically known, so use the explicit resource/action lookup
helpers in TypeScript:

```ts
import { CallbackClient } from 'haveapi-client';

const token = process.env.VPSADMIN_TOKEN;
if (!token) throw new Error('Set VPSADMIN_TOKEN to an existing API token');

const api = new CallbackClient('https://api.vpsfree.cz');
api.authenticate('token', { token }, (client, ready) => {
  if (!ready) {
    console.error('Authentication or API discovery failed');
    return;
  }

  try {
    const resource = CallbackClient.findResource(client, ['vps']);
    const action = CallbackClient.findAction(resource, 'list');
    action.directInvoke({ limit: 10 }, (owner, reply) => {
      if (!reply.isOk()) {
        console.error(reply.message(), reply.envelope.errors);
        return;
      }
      console.log(reply.response(), reply.meta());
    });
  } catch (error) {
    console.error('Unable to look up or invoke the action:', error);
  }
});
```

`directInvoke` supplies the raw callback `Response` wrapper, including
`response()`, `meta()`, `message()` and `envelope.errors`. It does not materialize
a resource list. `findResource` accepts a path of exact resource names;
`findAction` accepts that resource and an action name. Missing or ambiguous names
throw `ProtocolError`. These helpers also reach names that collide with local
JavaScript properties.

### TypeScript with async-await

```ts
import { AsyncClient, AsyncResourceList } from 'haveapi-client';

async function main(): Promise<void> {
  const token = process.env.VPSADMIN_TOKEN;
  if (!token) throw new Error('Set VPSADMIN_TOKEN to an existing API token');

  const api = new AsyncClient('https://api.vpsfree.cz');
  await api.authenticate('token', { token });
  const { value: vpses } = await api.resource('vps').action('list')<AsyncResourceList>({
    params: { limit: 10 }
  });
  vpses.each(vps => console.log(vps.get('id'), vps.get('hostname')));
}

main().catch(console.error);
```

The generic type argument specifies the expected result type; it does not generate endpoint
types or validate application fields at runtime. The same explicit
`resource(name).action(name)` form works in JavaScript. Use
`AsyncResourceInstance` as the result type for an `object` action such as `show`.

## Common usage

### Public resources and API versions

Use `api.setup((client, ready) => { ... })` with callbacks or `await api.setup()`
with the async interface when authentication is unnecessary. Check `ready`
before callback calls, and handle async setup rejection as in the quickstarts.

To select a specific API version, pass `{ version: 'API_VERSION' }` to either
constructor, replacing `API_VERSION` with the chosen version. Keep the URL at
the API root. Discovery and described actions use the paths advertised by the
server. The
[request reference](doc-async-client.md#path-based-requests) explains mounted
URLs and the different path rules for low-level requests.

### IDs and input parameters

After discovery or authentication, pass path IDs before the input parameters.
For example, to fetch VPS 101 using callbacks:

```js
api.vps.show(101, (client, vps) => {
  if (!vps.isOk()) {
    console.error('Unable to fetch VPS 101');
    return;
  }
  console.log(vps.id, vps.hostname);
});
```

For the async interface, call `await api.vps.show(101)` inside an async function
with rejection handling. Put action input under `params`, as in the list
quickstarts. Actions that operate on a collection take only the IDs present in
their described path. In particular, a top-level collection create action does
not take an existing object's ID. Required create fields depend on the API.

### Metadata and associations

Callback calls accept metadata inside the parameter object:

```js
api.vps.list({
  limit: 10,
  meta: { count: true, includes: 'user,node__location' }
}, (client, vpses) => {
  if (!vpses.isOk()) {
    console.error('Unable to list VPSes');
    return;
  }
  console.log('Received:', vpses.length, 'Total:', vpses.totalCount);
  vpses.each(vps => console.log(vps.id, vps.hostname));
});
```

The requested callback associations are prefetched when supported by the API.
Async calls put `meta` alongside `params`, for example
`{ params: { limit: 10 }, meta: { count: true } }`, and expose metadata through
`response.meta`. Async association getters never perform network I/O; use
`loadAssociation(name)` explicitly. See [async resources](doc-async-resources.md)
for binding, association loading and `new()` / `save()` behavior.

### Authentication and language

Both interfaces support HTTP basic authentication, existing tokens and token
acquisition. Use `{ user, password }` instead of `{ token }` to request a token
when those are the server's described credentials. With basic authentication,
use the method name `'basic'` and `{ user, password }`; HaveAPI servers normally
disable this method for browsers.

For multi-factor token authentication, callback options accept
`callback(action, parameters, cont)`. Return the next input object immediately,
or call `cont(input)` later and return nothing. Use only one continuation per
challenge. Async options accept `onChallenge(action, parameters)`, which returns
the next input object or a Promise for it. See
[async authentication](doc-async-client.md#setup-and-authentication) and the
[callback API reference](https://projects.vpsfree.cz/haveapi-client-js/ref/).

Pass `{ language: 'cs' }` to either constructor to request translated messages
and local validation errors. The default header is `Accept-Language`; set
`language_header` for a custom header. Set the language before setup or
authentication to load translated descriptions.

## Advanced usage and reference

- [Async requests, authentication and errors](doc-async-client.md): low-level
  `request()` for known paths, timeouts, abort signals and server completion.
- [Async resources and binding](doc-async-resources.md): action options, result
  layouts, identity, saves and association loading.
- [Callback API reference](https://projects.vpsfree.cz/haveapi-client-js/ref/):
  resources, actions, responses and hooks. `api.after('setup', callback)` and
  `api.after('authenticated', callback)` register readiness hooks, including
  after the event has occurred.
- [Callback action options](https://projects.vpsfree.cz/haveapi-client-js/ref/HaveAPI.Client.Action.html#invoke__anchor):
  long-running actions use `onReply`, `onStateChange` and `onDone`. The initial
  reply reports acceptance. Inspect `state.finished` and `state.status` in
  `onStateChange` for the terminal job outcome; `onDone` receiving an `isOk()`
  reply alone does not prove job success. Cancellation is available through
  `state.cancel(options)` when `state.canCancel` is true. Async callers use
  `waitForCompletion()` separately, as described in the async reference.

## Development

See [build preparation and checks](test/README.md) for the Nix environment,
compiler compatibility, documentation generation and test commands.

## License

The HaveAPI JavaScript client is released under the MIT license.
