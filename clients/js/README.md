haveapi-client-js
=================
A client library for HaveAPI based APIs in JavaScript.

Installation
------------
 - Manual - Copy `dist/haveapi-client.js` to your project
 - Node.js - `npm install haveapi-client`
 - bower - `bower install haveapi-client`

The client is authored in TypeScript. The package ships the UMD JavaScript bundle
at `dist/haveapi-client.js` and generated declarations at `dist/types/haveapi.d.ts`.
Use it from JavaScript or TypeScript without compiling the library yourself.

Usage
-----
On the web:

```html
<script src="haveapi-client.js"></script>
```

With NodeJS:

```js
var HaveAPI = require('haveapi-client');
```

Use `CallbackClient` for callbacks or `AsyncClient` for Promises. `Client`
remains supported as an alias of `CallbackClient`: both names refer to the same
constructor, prototype and static helpers. Its runtime constructor name remains
`Client`.

### AsyncClient

For a Promise-based path request, the API base already includes its version:

```js
const { AsyncClient } = require('haveapi-client');

async function main() {
  const api = new AsyncClient('https://api.example.test/v7.0');
  const result = await api.request({ method: 'GET', path: '/items' });
  console.log(result.data);
}

main().catch(console.error);
```

This request does not need `setup()`. See [async requests and authentication](doc-async-client.md)
and [async resources and binding](doc-async-resources.md) for description-based
resource access, authentication, errors and completion waiting.

For discovery and described actions, configure the API root including its mount,
such as `https://api.example.test/mount/`, and select the version with
`{version: '2'}`. The server's advertised action and authentication paths already
specify the route, including the mount and any version prefix. Clients resolve
these paths from the origin root.
Raw `AsyncClient.request` paths remain relative to the configured API base.
Applications with manually built or cached API-relative descriptors under a
mounted base must refresh those descriptors from OPTIONS.

### CallbackClient

Create a callback client instance:

```js
var api = new HaveAPI.CallbackClient("http://your.api.tld");
```

Request translated API messages and translate local client-side validation
errors by passing `language`:

```js
var api = new HaveAPI.CallbackClient("http://your.api.tld", { language: "cs" });
```

The value is sent in `Accept-Language` by default. Use `language_header` when
the API is configured with a custom language header. Set the language before
`setup()` or `authenticate()` so translated validator descriptions are loaded
from the server.

Before using callback resource actions, set up the callback client:

```js
api.setup(function() {
	console.log("The client is ready to roll");
});
```

Use the public lookup helpers after discovery to access resources and actions
by their exact names. They also support TypeScript without endpoint-specific
types:

```ts
import { CallbackClient } from 'haveapi-client';

const api = new CallbackClient('https://api.example.test/mount/', {version: '2'});
api.setup((client, ready) => {
  if (!ready) return;
  const resource = CallbackClient.findResource(client, ['widget']);
  const action = CallbackClient.findAction(resource, 'show');
  action.directInvoke(7, (owner, response) => {
    if (!response.isOk()) {
      console.error(response.message(), response.envelope.errors);
      return;
    }
    console.log(response.response(), response.meta());
  });
});
```

`findAction` accepts a resource returned by `findResource` (including a bound
resource). Canonical action names take priority; aliases resolve only when they
identify one action. Missing or ambiguous names raise `ProtocolError`. Names
that collide with JavaScript properties remain accessible through these helpers.
Existing direct properties and the resource's `actions` name array keep their
existing behavior. `directInvoke` always supplies a raw `Response`; ordinary
invocation may return resource instances or lists according to the description.

### Authentication
haveapi-client-js supports HTTP basic and token authentication. However, the HTTP basic
method is by default not allowed by HaveAPI to be used from web browsers.

#### HTTP basic

```js
api.setup(function() {
	console.log("The client is ready to roll");

	api.authenticate('basic', {
			user: 'yourname',
			password: 'yourpassword'
		}, function(c, status) {
		console.log("Are we authenticated?", status);
	});
});
```

#### Token authentication
Request a token:

```js
api.setup(function() {
	console.log("The client is ready to roll");

	api.authenticate('token', {
			user: 'yourname',
			password: 'yourpassword'
		}, function(c, status) {
		console.log("Are we authenticated?", status);
		console.log("Auth token is:", api.authProvider.token);
	});
});
```

Use an existing token:

```js
api.setup(function() {
	console.log("The client is ready to roll");

	api.authenticate('token', {
			token: 'qwertyuiopasdfghjkl',
		}, function(c, status) {
		console.log("Are we authenticated?", status);
	});
});
```

It is possible to avoid calling setup and use only authenticate, if
you won't use the client before authentication anyway.

```js
api.authenticate('token', {
		token: 'qwertyuiopasdfghjkl',
	}, function(c, status) {
	console.log("The client is set up");
	console.log("Are we authenticated?", status);
});
```

## Multi-factor token authentication
The token authentication also supports multi-factor authentication, i.e. the
API server may require clients to call multiple authentication actions with
different credentials. It is necessary to implement a callback function which
is called when additional authentication steps are needed. The function
either returns input parameters to use for authentication, or invokes the
callback which it gets as an argument.

```js
api.authenticate('token', {
		user: 'yourname',
		password: 'yourpassword',
		callback: function (action, params, cont) {
			console.log("The server requires additional authentication", action);

			// Either call the callback whenever ready
			cont({"code": 123456});

			// Or return the parameters immediately
			return {"code": 123456};
		}
	}, function(c, status) {
	console.log("Are we authenticated?", status);
	console.log("Auth token is:", api.authProvider.token);
});
```

### Access resources and actions
Resources and actions can be used only after the client has been set up
or authenticated.

```js
// Get a resource
api.vps.show(101, function(c, vps) {
	console.log("Received VPS:", vps.id, vps.hostname);
});

// Create a resource
api.vps.create(101, {
		hostname: 'something',
		and: 'others'
	}, function(c, reply) {
	console.log('Created VPS?', reply.isOk());
});

// It's also possible to create it with an empty instance
var myvps = api.vps.new();
myvps.hostname = 'something_different';
myvps.save(function(c, vps) {
	console.log('created a vps?', vps.isOk(), vps.id);
});

// Lists of objects
api.vps.list({limit: 10}, function(c, vpses) {
	console.log('received a list of vpses', vpses.isOk(), vpses.length);

	vpses.each(function(vps) {
		console.log('containing', vps.id, vps.hostname);
	});
});

```

### Blocking actions
HaveAPI has support for long-running actions. Progress of such actions can be monitored.
The client has a callback to get updates about the action's state and a callback that
is called when the action is finished.

Notice that the callbacks are passed in a different way, see the
[documentation](https://projects.vpsfree.cz/haveapi-client-js/ref/HaveAPI.Client.Action.html#invoke__anchor)
to learn more about it.

```js
api.vps.restart(101, {
    // onReply is called when the API server responds. It is the final callback
    // for non-blocking actions.
    onReply: function (c, reply) {
        console.log('Server replied, action is being executed');
    },

    // Called regularly when the action's state changes
    onStateChange: function (c, reply, state) {
        console.log('Current progress:', state.progress.toString());
    },

    // Called when the action finishes
    onDone: function (c, reply) {
        console.log('Action done!');
    }
})
```

Some actions can be cancelled from the `onStateChange` callback if
`state.canCancel` is `true`.

```js
...
onStateChange: function (c, reply, state) {
    if (state.canCancel) {
        // Note that the cancel operation can also be blocking. That depends on the
        // API server.
        state.cancel({
            onReply: function () { ... },
            onStateChange: function () { ... },
            onDone: function () { ... }
        });
    }
}
...
```

### Metadata
Metadata may be used to prefetch associated resources or get total item count.

```js
api.vps.list({
		limit: 10,
		meta: {count: true, includes: 'user,node__location'}
	}, function(c, vpses) {
	console.log('received a list of vpses', vpses.isOk());
	console.log('number of received vpses', vpses.length);
	console.log('total count of vpses', vpses.tocalCount)

	vpses.each(function(vps) {
		// Associations user, node and node__location are prefetched.
		// They can be accessed immediately without any additional
		// HTTP request.
		console.log('VPS', vps.id, vps.hostname, vps.user.login, vps.node.name, vps.node.location.label);
	});
});
```

### Hooks
Sometimes it is needed to use the client independently on multiple places, but
to only have one instance and setup/authenticate just once.

There are two hooks available: `setup` and `authenticated`. They are both called
after the event occurs. A hook may be registered multiple times and it does not matter
if it is registered before (the callback is queued) or after (it is called right away)
the event actually happens.

```js
// The client is initialized, set up and authenticated somewhere else in the
// code. Something just needs to be done when it is ready.
api.after('setup', function() {
	console.log("The client is set up");
});

api.after('authenticated', function() {
	console.log("The client is authenticated");
})
```

Documentation
-------------
https://projects.vpsfree.cz/haveapi-client-js/ref/

Development tool compatibility
------------------------------
The pinned Node 24 shell builds the client with TypeScript 6.0.3 and Rollup.
TypeScript 6 supports the bundle's ES5 target; TypeScript 7 removes it. The
affected build and consumer configs set `ignoreDeprecations: "6.0"` for ES5 and
`moduleResolution: "node"`, the legacy Node10 resolution algorithm. Strict type
and declaration checks and an ES5 parser still validate the emitted package.
The async client's runtime requirements remain unchanged.

JSDoc uses `markdown-it` 15.0.3 and `markdown-it-anchor` 10.0.0 through overrides
scoped to JSDoc. The compatibility suite checks heading renders, links and
generated API navigation. These are build tools; package consumers use the
bundled JavaScript and emitted declarations.
See [the check commands](test/README.md).

License
-------
haveapi-client-js is released under the MIT license.
