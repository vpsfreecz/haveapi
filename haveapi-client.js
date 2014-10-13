(function(root){
/**
 * @namespace HaveAPI
 * @author Jakub Skokan <jakub.skokan@vpsfree.cz>
 */


/********************************************************************************/
/*******************************  HAVEAPI.CLIENT  *******************************/
/********************************************************************************/


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
		 * @member {Object} HaveAPI.Client#description Description received from the API.
		 */
		this.description = null;
		
		/**
		 * @member {Array} HaveAPI.Client#resources A list of top-level resources attached to the client.
		 */
		this.resources = [];
		
		/**
		 * @member {Object} HaveAPI.Client#authProvider Selected authentication provider.
		 */
		this.authProvider = new root.HaveAPI.Client.Authentication.Base();
	}
};

var c = root.HaveAPI.Client;

/** @constant HaveAPI.Client.Version */
c.Version = '0.4.0-dev';

/**
 * @callback HaveAPI.Client~doneCallback
 * @param {HaveAPI.Client} client
 * @param {Boolean} status true if the task was successful
 */

/**
 * @callback HaveAPI.Client~replyCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Response} response
 */

/**
 * Setup resources and actions as properties and functions.
 * @method HaveAPI.Client#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
c.prototype.setup = function(callback) {
	var that = this;
	
	this.fetchDescription(function(status, response) {
		that.description = response.response;
		that.attachResources();
		
		callback(that, true);
	});
};

/**
 * Provide the description and setup the client without asking the API.
 * @method HaveAPI.Client#useDescription
 * @param {Object} description
 */
c.prototype.useDescription = function(description) {
	this.description = description;
	this.attachResources();
}

/**
 * Fetch the description from the API.
 * @method HaveAPI.Client#fetchDescription
 * @private
 * @param {HaveAPI.Client.Http~replyCallback} callback
 */
c.prototype.fetchDescription = function(callback) {
	this.http.request({
		method: 'OPTIONS',
		url: this.url + "/?describe=default",
		callback: callback
	});
};

/**
 * Attach API resources from the description to the client.
 * @method HaveAPI.Client#attachResources
 * @private
 */
c.prototype.attachResources = function() {
	// Detach existing resources
	if (this.resources.length > 0) {
		this.destroyResources();
	}
	
	for(var r in this.description.resources) {
		console.log("Attach resource", r);
		this.resources.push(r);
		
		this[r] = new root.HaveAPI.Client.Resource(this, r, this.description.resources[r], []);
	}
};

/**
 * Authenticate using selected authentication method.
 * It is possible to avoid calling {@link HaveAPI.Client#setup} before authenticate completely,
 * when it's certain that the client will be used only after it is authenticated. The client
 * will be then set up more efficiently.
 * @method HaveAPI.Client#authenticate
 * @param {string} method name of authentication provider
 * @param {Object} opts a hash of options that is passed to the authentication provider
 * @param {HaveAPI.Client~doneCallback} callback called when the authentication is finished
 */
c.prototype.authenticate = function(method, opts, callback) {
	var that = this;
	
	if (!this.description) {
		// The client has not yet been setup.
		// Fetch the description, do NOT attach the resources, use it only to authenticate.
		
		this.fetchDescription(function(status, response) {
			that.description = response.response;
			that.authenticate(method, opts, callback);
		});
		
		return;
	}
	
	this.authProvider = new c.Authentication.providers[method](this, opts, this.description.authentication[method]);
	
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
 * @param {HaveAPI.Client~doneCallback} callback
 */
c.prototype.logout = function(callback) {
	var that = this;
	
	this.authProvider.logout(function() {
		that.authProvider = new root.HaveAPI.Client.Authentication.Base();
		that.destroyResources();
		that.description = null;
		
		if (callback !== undefined)
			callback(that, true);
	});
};

/**
 * @method HaveAPI.Client#invoke
 * @param {HaveAPI.Client~replyCallback} callback
 */
c.prototype.invoke = function(action, params, callback) {
	console.log("executing", action, "with params", params, "at", action.preparedUrl);
	var that = this;
	
	var opts = {
		method: action.httpMethod(),
		url: this.url + action.preparedUrl,
		credentials: this.authProvider.credentials(),
		headers: this.authProvider.headers(),
		queryParameters: this.authProvider.queryParameters(),
		callback: function(status, response) {
			if(callback !== undefined) {
				callback(that, new root.HaveAPI.Client.Response(action, response));
			}
		}
	}
	
	var paramsInQuery = this.sendAsQueryParams(opts.method);
	
	if (paramsInQuery) {
		opts.url = this.addParamsToQuery(opts.url, action.namespace('input'), params);
		
	} else {
		var scopedParams = {};
		scopedParams[ action.namespace('input') ] = params;
		
		opts.params = scopedParams;
	}
	
	this.http.request(opts);
};

/**
 * Detach resources from the client.
 * @method HaveAPI.Client#destroyResources
 * @private
 */
c.prototype.destroyResources = function() {
	while (this.resources.length < 0) {
		delete this[ that.resources.shift() ];
	}
};

/**
 * Return true if the parameters should be sent as a query parameters,
 * which is the case for GET and OPTIONS methods.
 * @method HaveAPI.Client#sendAsQueryParams
 * @param {String} method HTTP method
 * @return {Boolean}
 * @private
 */
c.prototype.sendAsQueryParams = function(method) {
	return ['GET', 'OPTIONS'].indexOf(method) != -1;
}

/**
 * Add URL encoded parameters to URL.
 * Note that this method does not support object_list or hash_list layouts.
 * @method HaveAPI.Client#addParamsToQuery
 * @param {String} url
 * @param {String} namespace
 * @param {Object} params
 * @private
 */
c.prototype.addParamsToQuery = function(url, namespace, params) {
	var first = true;
	
	for (var key in params) {
		if (first) {
			if (url.indexOf('?') == -1)
				url += '?';
				
			else if (url[ url.length - 1 ] != '&')
				url += '&';
			
			first = false;
			
		} else url += '&';
		
		url += encodeURI(namespace) + '[' + encodeURI(key) + ']=' + encodeURI(params[key]);
	}
	
	return url;
}


/********************************************************************************/
/*************************  HAVEAPI.HTTP.CLIENT  ********************************/
/********************************************************************************/


/**
 * @class Http
 * @memberof HaveAPI.Client
 */
var http = c.Http = function() {};

/**
 * @callback HaveAPI.Client.Http~replyCallback
 * @param {Integer} status received HTTP status code
 * @param {Object} response received response
 */

/**
 * @method HaveAPI.Client.Http#request
 */
http.prototype.request = function(opts) {
	console.log("request to " + opts.method + " " + opts.url);
	var r = new XMLHttpRequest();
	
	if (opts.credentials === undefined)
		r.open(opts.method, opts.url);
	else
		r.open(opts.method, opts.url, true, opts.credentials.username, opts.credentials.password);
	
	for (var h in opts.headers) {
		r.setRequestHeader(h, opts.headers[h]);
	}
	
	if (opts.params !== undefined)
		r.setRequestHeader('Content-Type', 'application/json; charset=utf-8');
	
	r.onreadystatechange = function() {
		var state = r.readyState;
		console.log('state is ' + state);
		
		if (state == 4 && opts.callback !== undefined) {
			opts.callback(r.status, JSON.parse(r.responseText));
		}
	};
	
	if (opts.params !== undefined) {
		r.send(JSON.stringify( opts.params ));
		
	} else {
		r.send();
	}
};


/********************************************************************************/
/*********************  HAVEAPI.CLIENT.AUTHENTICATION  **************************/
/********************************************************************************/


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


/********************************************************************************/
/*******************  HAVEAPI.CLIENT.AUTHENTICATION.BASE  ***********************/
/********************************************************************************/


/**
 * @class Base
 * @classdesc Base class for all authentication providers. They do not have to inherit
 *            it directly, but must implement all necessary methods.
 * @memberof HaveAPI.Client.Authentication
 */
var base = c.Authentication.Base = function(client, opts, description){};

/**
 * Setup the authentication provider and call the callback.
 * @method HaveAPI.Client.Authentication.Base#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
base.prototype.setup = function(callback){};

/**
 * Logout, destroy all resources and call the callback.
 * @method HaveAPI.Client.Authentication.Base#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
base.prototype.logout = function(callback) {
	callback(this.client, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Base#credentials
 * @return {Object} credentials
 */
base.prototype.credentials = function(){};

/**
 * Returns an object with HTTP headers to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#headers
 * @return {Object} HTTP headers
 */
base.prototype.headers = function(){};

/**
 * Returns an object with query parameters to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#queryParameters
 * @return {Object} query parameters
 */
base.prototype.queryParameters = function(){};


/********************************************************************************/
/******************  HAVEAPI.CLIENT.AUTHENTICATION.BASIC  ***********************/
/********************************************************************************/


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

/**
 * @method HaveAPI.Client.Authentication.Basic#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
basic.prototype.setup = function(callback) {
	if(callback !== undefined)
		callback(this.client, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Basic#credentials
 * @return {Object} credentials
 */
basic.prototype.credentials = function() {
	return this.opts;
};


/********************************************************************************/
/*******************  HAVEAPI.CLIENT.AUTHENTICATION.TOKEN  **********************/
/********************************************************************************/


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
	
	/**
	 * @member {String} HaveAPI.Client.Authentication.Token#token The token received from the API.
	 */
	this.token = null;
};
token.prototype = new base();

/**
 * @method HaveAPI.Client.Authentication.Token#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
token.prototype.setup = function(callback) {
	if (this.opts.hasOwnProperty('token')) {
		this.token = this.opts.token;
		this.configured = true;
		
		if(callback !== undefined)
			callback(this.client, true);
	
	} else {
		this.requestToken(callback);
	}
};

/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
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
	
	this.resource.request(params, function(c, response) {
		if (response.isOk()) {
			var t = response.response();
			
			that.token = t.token;
			that.validTo = t.valid_to;
			that.configured = true;
			
			if(callback !== undefined)
				callback(that.client, true);
			
		} else {
			if(callback !== undefined)
				callback(that.client, false);
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
 * @param {HaveAPI.Client~doneCallback} callback
 */
token.prototype.logout = function(callback) {
	this.resource.revoke(null, function(c, reply) {
		callback(this.client, reply.isOk());
	});
};


/********************************************************************************/
/***************  HAVEAPI.CLIENT.AUTHENTICATION REGISTRATION  *******************/
/********************************************************************************/


// Register built-in providers
c.Authentication.registerProvider('basic', basic);
c.Authentication.registerProvider('token', token);


/********************************************************************************/
/************************  HAVEAPI.CLIENT.RESOURCE  *****************************/
/********************************************************************************/


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
		var names = [a].concat(description.actions[a].aliases);
		var actionInstance = new root.HaveAPI.Client.Action(this.client, this, a, description.actions[a], this.args);
		
		for(var i = 0; i < names.length; i++) {
			this.actions.push(names[i]);
			this[names[i]] = actionInstance;
		}
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


/********************************************************************************/
/*************************  HAVEAPI.CLIENT.ACTION  ******************************/
/********************************************************************************/


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

/**
 * Returns action's HTTP method.
 * @method HaveAPI.Client.Action#httpMethod
 * @return {String}
 */
a.prototype.httpMethod = function() {
	return this.description.method;
};

/**
 * Returns action's namespace.
 * @method HaveAPI.Client.Action#namespace
 * @param {String} direction input/output
 * @return {String}
 */
a.prototype.namespace = function(direction) {
	return this.description[direction].namespace;
};

/**
 * Returns action's layout.
 * @method HaveAPI.Client.Action#layout
 * @param {String} direction input/output
 * @return {String}
 */
a.prototype.layout = function(direction) {
	return this.description[direction].layout;
};

/**
 * Invoke the action.
 * This method has a variable number of arguments. Arguments are first applied
 * as object IDs in action URL. When there are no more URL parameters to fill,
 * the second last argument is an Object containing parameters to be sent.
 * The last argument is a {@link HaveAPI.Client~replyCallback} callback function.
 * 
 * The argument with parameters may be omitted, if the callback function
 * is in its place.
 * 
 * Arguments do not have to be passed to this method specifically. They may
 * be given to the resources above, the only thing that matters is their correct
 * order.
 * 
 * @example
 * // Call with parameters and a callback.
 * // The first argument '1' is a VPS ID.
 * api.vps.ip_address.list(1, {limit: 5}, function(c, reply) {
 * 		console.log("Got", reply.response());
 * });
 * 
 * @example
 * // Call only with a callback. 
 * api.vps.ip_address.list(1, function(c, reply) {
 * 		console.log("Got", reply.response());
 * });
 * 
 * @example
 * // Give parameters to resources.
 * api.vps(101).ip_address(33).delete();
 * 
 * @method HaveAPI.Client.Action#invoke
 */
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
	var hasParams = args.length > 0;
	var isFn = hasParams && args.length == 1 && typeof(args[0]) == "function";
	
	this.client.invoke(this, hasParams && !isFn ? args[0] : null, function(c, response) {
		that.preparedUrl = null;
		
		if (args.length > 1) {
			args[1](c, response);
			
		} else if(isFn) {
			args[0](c, response);
		}
	});
};


/********************************************************************************/
/************************  HAVEAPI.CLIENT.RESPONSE  *****************************/
/********************************************************************************/


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
