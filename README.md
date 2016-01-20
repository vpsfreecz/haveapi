haveapi-client-js
=================
A client library for HaveAPI based APIs in JavaScript.

Installation
------------
 - Manual - Copy `dist/haveapi-client.js` to your project
 - Node.js - `npm install haveapi-client`
 - bower - `bower install haveapi-client`

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

Create a client instance:

```js
api = new HaveAPI.Client("http://your.api.tld");
```

Before the client can be used, it must be set up:

```js
api.setup(function() {
	console.log("The client is ready to roll");
});
```

### Authentication
haveapi-client-js supports HTTP basic and token authentication. However, the HTTP basic
method is by default not allowed by HaveAPI to be used from web browsers.

#### HTTP basic

```js
api.setup(function() {
	console.log("The client is ready to roll");
	
	api.authenticate('basic', {
			username: 'yourname',
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
			username: 'yourname',
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

License
-------
haveapi-client-js is released under the MIT license.
