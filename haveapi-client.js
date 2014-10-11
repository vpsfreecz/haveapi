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
		this.resources = {};
		this.authProvider = new root.HaveAPI.Client.Authentication.Base();
	}
};

var c = root.HaveAPI.Client;

/** @constant Client.Version */
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
		
		that.resources = [];
		that.description = response.response;
		
		for(var r in that.description.resources) {
			console.log(r);
			that.resources.push(r);
			
			that[r] = new root.HaveAPI.Client.Resource(that, r, that.description.resources[r], []);
		}
		
		callback(that);
	});
}

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
}

/**
 * @method HaveAPI.Client#authenticate
 * @param {string} method name of authentication provider
 * @param {Object} opts a hash of options that is passed to the authentication provider
 * @param {Client~authCallback} callback called when the authentication is finished
 */
c.prototype.authenticate = function(method, opts, callback) {
	this.authProvider = new c.Authentication.providers[method](c, opts, this.description.authentication[method]);
	this.authProvider.setup(callback);
}

/**
 * @method HaveAPI.Client#logout
 */
c.prototype.logout = function(method, opts, callback) {
	
}

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
		header: this.authProvider.headers(),
		queryParameters: this.authProvider.queryParameters(),
		params: scopedParams,
		callback: function(status, response) {
			if(callback !== undefined) {
				callback(action, new root.HaveAPI.Client.Response(response));
			}
		}
	}
	
	this.http.request(opts);
}

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
}

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
}

basic.prototype.credentials = function() {
	return this.opts;
}

/**
 * @class Token
 * @classdesc Token authentication provider. Not implemented yet.
 * @memberof HaveAPI.Client.Authentication
 */
var token = c.Authentication.Token = function(){};
token.prototype = new base();

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
	console.log("add action", name, "to", resource.name);
	
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
}

a.prototype.httpMethod = function() {
	return this.description.method;
}

a.prototype.namespace = function(direction) {
	return this.description[direction].namespace;
}

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
	
	this.client.invoke(this, args[0], function() {
		this.preparedUrl = null;
		
		if (args.length > 1) {
			args[1]();
		}
	});
}

/**
 * @class Response
 * @memberof HaveAPI.Client
 */
var r = c.Response = function(action, response) {
	this.response = response;
}

})(window);
