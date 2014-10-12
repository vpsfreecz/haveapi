(function(root){
/**
 * @namespace HaveAPI
 * @author Jakub Skokan <jakub.skokan@vpsfree.cz>
 */
root.HaveAPI = {
	/**
	 * Create a new client for the API.
	 * @class Client
	 * @memberof HaveAPI
	 * @param {string} url base URL to the API
	 */
	Client: function(url) {
		this.url = url;
		this.http = new root.HaveAPI.Client.Http();
		
		/**
		 * @member {Array} HaveAPI.Client#resources a list of top-level resources attached to the client
		 */
		this.resources = [];
		
		/**
		 * @member {Object} HaveAPI.Client#authProvider selected authentication provider
		 */
		this.authProvider = new root.HaveAPI.Client.Authentication.Base();
	}
};

var c = root.HaveAPI.Client;

/** @constant HaveAPI.Client.Version */
c.Version = '0.4.0-dev';

/**
 * Setup resources and actions as properties and functions.
 * @method HaveAPI.Client#setup
 * @param {Client~setupCallback} callback
 */
c.prototype.setup = function(callback) {
	var that = this;
	
	this.fetchDescription(function(status, response) {
// 		console.log(status, response);
// 		console.log(response.response);
		
		// Detach existing resources
		if (that.resources.length > 0) {
			that.destroyResources();
		}
		
		that.description = response.response;
		
		for(var r in that.description.resources) {
			console.log("Attach resource", r);
			that.resources.push(r);
			
			that[r] = new root.HaveAPI.Client.Resource(that, r, that.description.resources[r], []);
		}
		
		callback(that);
	});
};

/**
 * @callback HaveAPI.Client~setupCallback
 * @param {Client} client instance
 */

c.prototype.fetchDescription = function(callback) {
	console.log("fetching description");
	
	this.http.request({
		method: 'OPTIONS',
		url: this.url + "/?describe=default",
		callback: callback
	});
};

/**
 * Authenticate using selected authentication method.
 * @method HaveAPI.Client#authenticate
 * @param {string} method name of authentication provider
 * @param {Object} opts a hash of options that is passed to the authentication provider
 * @param {Client~authCallback} callback called when the authentication is finished
 */
c.prototype.authenticate = function(method, opts, callback) {
	this.authProvider = new c.Authentication.providers[method](this, opts, this.description.authentication[method]);
	
	var that = this;
	
	this.authProvider.setup(function() {
		// Fetch new description, which may be different when authenticated
		that.setup(callback);
	});
};

/**
 * Logout, destroy the authentication provider.
 * {@link HaveAPI.Client#setup} must be called if you want to use
 * the client again.
 * @method HaveAPI.Client#logout
 */
c.prototype.logout = function(callback) {
	var that = this;
	
	this.authProvider.logout(function() {
		that.authProvider = new root.HaveAPI.Client.Authentication.Base();
		that.destroyResources();
		that.description = null;
		
		if (callback !== undefined)
			callback();
	});
};

/**
 * @method HaveAPI.Client#invoke
 */
c.prototype.invoke = function(action, params, callback) {
	console.log("executing", action, "with params", params, "at", action.preparedUrl);
	
	var scopedParams = {};
	scopedParams[ action.namespace('input') ] = params;
	
	var opts = {
		method: action.httpMethod(),
		url: this.url + action.preparedUrl,
		credentials: this.authProvider.credentials(),
		headers: this.authProvider.headers(),
		queryParameters: this.authProvider.queryParameters(),
		params: scopedParams,
		callback: function(status, response) {
			if(callback !== undefined) {
				callback(new root.HaveAPI.Client.Response(action, response));
			}
		}
	}
	
	this.http.request(opts);
};

c.prototype.destroyResources = function() {
	while (this.resources.length < 0) {
		delete this[ that.resources.shift() ];
	}
};

/**
 * @class Http
 * @memberof HaveAPI.Client
 */
var http = c.Http = function() {};

/**
 * @method HaveAPI.Client.Http#request
 */
http.prototype.request = function(opts) {
	console.log("request to " + opts.method + " " + opts.url);
	var r = new XMLHttpRequest();
	
	if(opts.credentials === undefined)
		r.open(opts.method, opts.url);
	else
		r.open(opts.method, opts.url, true, opts.credentials.username, opts.credentials.password);
	
	for(var h in opts.headers) {
		r.setRequestHeader(h, opts.headers[h]);
	}
	
	r.setRequestHeader('Content-Type', 'application/json; charset=utf-8');
	
	r.onreadystatechange = function() {
		var state = r.readyState;
		console.log('state is ' + state);
		
		if(state == 4 && opts.callback !== undefined) {
			opts.callback(r.status, JSON.parse(r.responseText));
		}
	};
	
	if(opts.params !== undefined) {
		r.send(JSON.stringify( opts.params ));
		
	} else {
		r.send();
	}
};

/**
 * @namespace Authentication
 * @memberof HaveAPI.Client
 */
c.Authentication = {
	/**
	 * @member {Array} providers An array of registered authentication providers.
	 * @memberof HaveAPI.Client.Authentication
	 */
	providers: {},
	
	/**
	 * Register authentication providers using this function.
	 * @func registerProvider
	 * @memberof HaveAPI.Client.Authentication
	 * @param {string} name must be the same name as in announced by the API
	 * @param {Object} provider class
	 */
	registerProvider: function(name, obj) {
		c.Authentication.providers[name] = obj;
	}
};

/**
 * @class Base
 * @classdesc Base class for all authentication providers. They do not have to inherit
 *            it directly, but must implement all necessary methods.
 * @memberof HaveAPI.Client.Authentication
 */
var base = c.Authentication.Base = function(client, opts, description){};
base.prototype.setup = function(callback){};
base.prototype.logout = function(callback) {
	callback();
};
base.prototype.credentials = function(){};
base.prototype.headers = function(){};
base.prototype.queryParameters = function(){};

/**
 * @class Basic
 * @classdesc Authentication provider for HTTP basic auth.
 *            Unfortunately, this provider probably won't work in most browsers
 *            because of their security considerations.
 * @memberof HaveAPI.Client.Authentication
 */
var basic = c.Authentication.Basic = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
};
basic.prototype = new base();

basic.prototype.setup = function(callback) {
	if(callback !== undefined)
		callback();
};

basic.prototype.credentials = function() {
	return this.opts;
};

/**
 * @class Token
 * @classdesc Token authentication provider.
 * @memberof HaveAPI.Client.Authentication
 */
var token = c.Authentication.Token = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
	this.description = description;
	this.configured = false;
};
token.prototype = new base();

/**
 * @method Token#setup
 */
token.prototype.setup = function(callback) {
	if (this.opts.hasOwnProperty('token')) {
		this.token = this.opts.token;
		this.configured = true;
		
		if(callback !== undefined)
			callback(this.client);
	
	} else {
		this.requestToken(callback);
	}
};

/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 */
token.prototype.requestToken = function(callback) {
	this.resource = new root.HaveAPI.Client.Resource(this.client, 'token', this.description.resources.token, []);
	
	var params = {
		login: this.opts.username,
		password: this.opts.password,
		lifetime: this.opts.lifetime || 'renewable_auto'
	};
	
	if(this.opts.interval !== undefined)
		params.interval = this.opts.interval;
	
	var that = this;
	
	this.resource.request(params, function(response) {
		if (response.isOk()) {
			console.log("got token!", response.response().token);
			
			var t = response.response();
			
			that.token = t.token;
			that.validTo = t.valid_to;
			that.configured = true;
			
			if(callback !== undefined)
				callback(that.client);
			
		} else {
			console.log("Not ok :/", response.message());
		}
	});
};

/**
 * @method HaveAPI.Client.Authentication.Token#headers
 */
token.prototype.headers = function(){
	if(!this.configured)
		return;
	
	var ret = {};
	ret[ this.description.http_header ] = this.token;
	
	return ret;
};

/**
 * @method HaveAPI.Client.Authentication.Token#logout
 */
token.prototype.logout = function(callback) {
	this.resource.revoke(null, callback);
};


// Register built-in providers
c.Authentication.registerProvider('basic', basic);
c.Authentication.registerProvider('token', token);


/**
 * @class Resource
 * @memberof HaveAPI.Client
 */
var r = c.Resource = function(client, name, description, args){
	this.client = client;
	this.name = name;
	this.description = description;
	this.args = args;
	this.resources = [];
	this.actions = [];
	
	for(var r in description.resources) {
		this.resources.push(r);
		
		this[r] = new root.HaveAPI.Client.Resource(this.client, r, description.resources[r], this.args);
	}
	
	for(var a in description.actions) {
		this.actions.push(a);
		
		this[a] = new root.HaveAPI.Client.Action(this.client, this, a, description.actions[a], this.args);
// 		this[a] = function() {
// 			// execute action
// 		}
	}
	
	var that = this;
	var fn = function() {
		return new c.Resource(that.client, that.name, that.description, that.args.concat(Array.prototype.slice.call(arguments)));
	};
	fn.__proto__ = this;
	
	return fn;
};

r.prototype.applyArguments = function(args) {
	for(var i = 0; i < args.length; i++) {
		this.args.push(args[i]);
	}
	
	return this;
}

/**
 * @class Action
 * @memberof HaveAPI.Client
 */
var a = c.Action = function(client, resource, name, description, args) {
	console.log("Attach action", name, "to", resource.name);
	
	this.client = client;
	this.resource = resource;
	this.name = name;
	this.description = description;
	this.args = args;
	
	var that = this;
	var fn = function() {
		var new_a = new c.Action(that.client, that.resource, that.name, that.description, that.args.concat(Array.prototype.slice.call(arguments)));
		return new_a.invoke();
	};
	fn.__proto__ = this;
	
	return fn;
};

a.prototype.httpMethod = function() {
	return this.description.method;
};

a.prototype.namespace = function(direction) {
	return this.description[direction].namespace;
};

a.prototype.layout = function(direction) {
	return this.description[direction].layout;
};

a.prototype.invoke = function() {
	var args = this.args.concat(Array.prototype.slice.call(arguments));
	var rx = /(:[a-zA-Z\-_]+)/;
	
	this.preparedUrl = this.description.url;
	
	while (args.length > 0) {
		if (this.preparedUrl.search(rx) == -1)
			break;
		
		this.preparedUrl = this.preparedUrl.replace(rx, args.shift());
	}
	
	if (args.length == 0 && this.preparedUrl.search(rx) != -1) {
		throw {
			name:    'UnresolvedArguments',
			message: "Unable to execute action '"+ this.name +"': unresolved arguments"
		}
	}
	
	var that = this;
	
	this.client.invoke(this, args.length > 0 ? args[0] : null, function(response) {
		that.preparedUrl = null;
		
		if (args.length > 1) {
			args[1](response);
		}
	});
};

/**
 * @class Response
 * @memberof HaveAPI.Client
 */
var r = c.Response = function(action, response) {
	this.action = action;
	this.envelope = response;
};

/**
 * Returns true if the request was successful.
 * @method HaveAPI.Client.Response#isOk
 * @return {Boolean}
 */
r.prototype.isOk = function() {
	return this.envelope.status;
};

/**
 * Returns the namespaced response if possible.
 * @method HaveAPI.Client.Response#response
 * @return {Object} response
 */
r.prototype.response = function() {
	switch (this.action.layout('output')) {
		case 'object':
		case 'object_list':
		case 'hash':
		case 'hash_list':
			return this.envelope.response[ this.action.namespace('output') ];
		
		default:
			return this.envelope.response;
	}
};

/**
 * Return the error message received from the API.
 * @method HaveAPI.Client.Response#message
 * @return {String}
 */
r.prototype.message = function() {
	return this.envelope.message;
};

})(window);
