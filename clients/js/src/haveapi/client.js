/**
 * Create a new client for the API.
 * @class Client
 * @memberof HaveAPI
 * @param {string} url base URL to the API
 * @param {Object} opts
 */
function Client(url, opts) {
	while (url.length > 0) {
		if (url[ url.length - 1 ] == '/')
			url = url.substr(0, url.length - 1);

		else break;
	}

	/**
	 * @member {Object} HaveAPI.Client#_private
	 * @protected
	 */
	this._private = {
		url: url,
		version: (opts !== undefined && opts.version !== undefined) ? opts.version : null,
		description: null,
		debug: (opts !== undefined && opts.debug !== undefined) ? opts.debug : 0,
	};

	this._private.hooks = new Client.Hooks(this._private.debug);
	this._private.http = new Client.Http(this._private.debug);

	/**
	 * @member {Object} HaveAPI.Client#apiSettings An object containg API settings.
	 */
	this.apiSettings = null;

	/**
	 * @member {Array} HaveAPI.Client#resources A list of top-level resources attached to the client.
	 */
	this.resources = [];

	/**
	 * @member {Object} HaveAPI.Client#authProvider Selected authentication provider.
	 */
	this.authProvider = new Client.Authentication.Base();
}

/** @constant HaveAPI.Client.Version */
Client.Version = '0.27.0';

/** @constant HaveAPI.Client.ProtocolVersion */
Client.ProtocolVersion = '2.0';

/**
 * @namespace Exceptions
 * @memberof HaveAPI.Client
 */
Client.Exceptions = {};

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
 * @callback HaveAPI.Client~versionsCallback
 * @param {HaveAPI.Client} client
 * @param {Boolean} status
 * @param {Object} versions
 */

/**
 * @callback HaveAPI.Client~actionStateCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Response} response
 * @param {HaveAPI.Client.ActionState} state
 */

/**
 * Action call parameters
 * @typedef {Object} HaveAPI.Client~ActionCall
 * @property {Object} params - Input parameters
 * @property {Object} meta - Input meta parameters
 * @property {Boolean} block
 * @property {Integer} blockInterval
 * @property {Integer} blockUpdateIn
 * @property {HaveAPI.Client~replyCallback} onReply - called when the API responds
 * @property {HaveAPI.Client~actionStateCallback} onStateChange - called when the
 *                                                                action's state changes
 * @property {HaveAPI.Client~replyCallback} onDone - called when the blocking action finishes
 */

/**
 * Setup resources and actions as properties and functions.
 * @method HaveAPI.Client#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.setup = function(callback) {
	var that = this;

	this.fetchDescription(function(status, extract) {
		var desc = null;

		try {
			desc = extract.call();

		} catch (e) {
			return callback(that, false);
		}

		that._private.description = extract.call();
		that.createSettings();
		that.attachResources();

		callback(that, true);
		that._private.hooks.invoke('after', 'setup', that, true);
	});
};

/**
 * Provide the description and setup the client without asking the API.
 * @method HaveAPI.Client#useDescription
 * @param {Object} description
 */
Client.prototype.useDescription = function(description) {
	this._private.description = description;
	this.createSettings();
	this.attachResources();
};

/**
 * Call a callback with an object with list of available versions
 * and the default one.
 * @method HaveAPI.Client#availableVersions
 * @param {HaveAPI.Client~versionsCallback} callback
 */
Client.prototype.availableVersions = function(callback) {
	var that = this;

	this.fetchDescription(function (status, extract) {
		var versions = null;

		try {
			versions = extract.call();
		} catch (e) {}

		callback(that, status && !(versions === null), versions);

	}, '/?describe=versions');
};

/**
 * @callback HaveAPI.Client~isCompatibleCallback
 * @param {mixed} compatible 'compatible', 'imperfect' or false
 */

/**
 * @method HaveAPI.Client#isCompatible
 * @param {HaveAPI.Client~isCompatibleCallback}
 */
Client.prototype.isCompatible = function(callback) {
	var that = this;

	this.fetchDescription(function (status, extract) {

		try {
			extract.call();

			if (that._private.protocolVersion == Client.ProtocolVersion)
				callback('compatible');

			else
				callback('imperfect');

		} catch (e) {
			if (e instanceof Client.Exceptions.ProtocolError)
				callback(false);

			else
				throw e;
		}

	}, '/?describe=versions');
}

/**
 * @callback HaveAPI.Client~descriptionCallback
 * @param {Boolean} status true if the description was successfuly fetched
 * @param {function} extract function that attempts to return the description
 */

/**
 * Fetch the description from the API.
 * @method HaveAPI.Client#fetchDescription
 * @private
 * @param {HaveAPI.Client.Http~descriptionCallback} callback
 * @param {String} path server path to query for
 */
Client.prototype.fetchDescription = function(callback, path) {
	var that = this;
	var url = this._private.url;

	if (path === undefined)
		url += (this._private.version ? "/v"+ this._private.version +"/" : "/?describe=default");
	else
		url += path;

	this._private.http.request({
		method: 'OPTIONS',
		url: url,
		credentials: this.authProvider.credentials(),
		headers: this.authProvider.headers(),
		queryParameters: this.authProvider.queryParameters(),
		callback: function (status, response) {
			callback(status == 200, function () {
				if (!response)
					throw new Client.Exceptions.ProtocolError('Failed to fetch the API description');

				if (response.version === undefined) {
					throw new Client.Exceptions.ProtocolError(
						'Incompatible protocol version: the client uses v'+ Client.ProtocolVersion +
						' while the API server uses an unspecified version (pre 1.0)'
					);
				}

				that._private.protocolVersion = response.version;

				if (response.version == Client.ProtocolVersion) {
					return response.response;
				}

				v1 = response.version.split('.');
				v2 = Client.ProtocolVersion.split('.');

				if (v1[0] != v2[0]) {
					throw new Client.Exceptions.ProtocolError(
						'Incompatible protocol version: the client uses v'+ Client.ProtocolVersion +
						' while the API server uses v'+ response.version
					);
				}

				console.log(
					'WARNING: The client uses protocol v'+ Client.ProtocolVersion +
					' while the API server uses v'+ response.version
				);

				return response.response;
			});
		}
	});
};

/**
 * Attach API resources from the description to the client.
 * @method HaveAPI.Client#attachResources
 * @private
 */
Client.prototype.attachResources = function() {
	// Detach existing resources
	if (this.resources.length > 0) {
		this.destroyResources();
	}

	for(var r in this._private.description.resources) {
		if (this._private.debug > 10)
			console.log("Attach resource", r);

		this[r] = new Client.Resource(
			this,
			null,
			r,
			this._private.description.resources[r],
			[]
		);

		this.resources.push(this[r]);
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
 * @param {Boolean} reset if false, the client will not be set up again, defaults to true
 */
Client.prototype.authenticate = function(method, opts, callback, reset) {
	var that = this;

	if (reset === undefined) reset = true;

	if (!this._private.description) {
		// The client has not yet been setup.
		// Fetch the description, do NOT attach the resources, use it only to authenticate.

		this.fetchDescription(function(status, extract) {
			that._private.description = extract.call();
			that.createSettings();
			that.authenticate(method, opts, callback);
		});

		return;
	}

	this.authProvider = new Authentication.providers[method](this, opts, this._private.description.authentication[method]);

	this.authProvider.setup(function(c, status) {
		// Fetch new description, which may be different when authenticated
		if (status && reset) {
			that.setup(function(c2, status2) {
				callback(c2, status2);
				that._private.hooks.invoke('after', 'authenticated', that, true);
			});

		} else {
			callback(that, status);
			if (status)
				that._private.hooks.invoke('after', 'authenticated', that, true);
		}
	});
};

/**
 * Logout, destroy the authentication provider.
 * {@link HaveAPI.Client#setup} must be called if you want to use
 * the client again.
 * @method HaveAPI.Client#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.logout = function(callback) {
	var that = this;

	this.authProvider.logout(function() {
		that.authProvider = new Client.Authentication.Base();
		that.destroyResources();
		that._private.description = null;

		if (callback !== undefined)
			callback(that, true);
	});
};

/**
 * Always calls the callback with {@link HaveAPI.Client.Response} object. It does
 * not interpret the response.
 * @method HaveAPI.Client#directInvoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.directInvoke = function(action, opts) {
	if (this._private.debug > 5)
		console.log("Executing", action, "with opts", opts, "at", action.preparedPath);

	var that = this;
	var block = opts.block === undefined ? true : opts.block;

	var httpOpts = {
		method: action.httpMethod(),
		url: this._private.url + action.preparedPath,
		credentials: this.authProvider.credentials(),
		headers: this.authProvider.headers(),
		queryParameters: this.authProvider.queryParameters(),
		callback: function(status, response) {
			var res = new Client.Response(action, response);

			if(opts.onReply !== undefined)
				opts.onReply(that, res);

			if (action.description.blocking && res.meta().action_state_id && opts.block) {
				if (opts.onStateChange || opts.onDone) {
					Action.waitForCompletion({
						id: res.meta().action_state_id,
						client: that,
						reply: res,
						blockInterval: opts.blockInterval,
						blockUpdateIn: opts.blockUpdateIn,
						onStateChange: opts.onStateChange,
						onDone: opts.onDone
					});
				}
			}
		}
	};

	var paramsInQuery = this.sendAsQueryParams(httpOpts.method);
	var metaNs = this.apiSettings.meta.namespace;

	if (paramsInQuery) {
		httpOpts.url = this.addParamsToQuery(
			httpOpts.url,
			action.namespace('input'),
			opts.params
		);

		if (opts.meta) {
			httpOpts.url = this.addParamsToQuery(
				httpOpts.url,
				metaNs,
				opts.meta
			);
		}

	} else {
		var scopedParams = {};
		var ns = action.namespace('input');

		if (ns)
			scopedParams[ns] = opts.params;

		if (opts.meta)
			scopedParams[metaNs] = opts.meta;

		httpOpts.params = scopedParams;
	}

	this._private.http.request(httpOpts);
};

/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#invoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.invoke = function(action, opts) {
	var that = this;
	var origOnReply = opts.onReply;
	var origOnBlock = opts.block === undefined ? true : opts.block;

	opts.onReply = function (status, response) {
		if (!origOnReply && (!action.description.blocking || (!opts.onStateUpdate && !opts.onDone)))
			return;

		var responseObject;

		switch (action.layout('output')) {
			case 'object':
				responseObject = new Client.ResourceInstance(
					that,
					action.resource._private.parent,
					action,
					response
				);
				break;

			case 'object_list':
				responseObject = new Client.ResourceInstanceList(that, action, response);
				break;

			default:
				responseObject = response;
		}

		if (origOnReply)
			origOnReply(that, responseObject);

		if (action.description.blocking && response.meta().action_state_id && origOnBlock) {
			if (opts.onStateChange || opts.onDone) {
				Action.waitForCompletion({
					id: response.meta().action_state_id,
					client: that,
					reply: responseObject,
					blockInterval: opts.blockInterval,
					blockUpdateIn: opts.blockUpdateIn,
					onStateChange: opts.onStateChange,
					onDone: opts.onDone
				});
			}
		}
	};

	opts.block = false;

	this.directInvoke(action, opts);
};

/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#after
 * @param {String} event setup or authenticated
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.after = function(event, callback) {
	this._private.hooks.register('after', event, callback);
}

/**
 * Set member apiSettings.
 * @method HaveAPI.Client#createSettings
 * @private
 */
Client.prototype.createSettings = function() {
	this.apiSettings = {
		meta: this._private.description.meta
	};
}

/**
 * Detach resources from the client.
 * @method HaveAPI.Client#destroyResources
 * @private
 */
Client.prototype.destroyResources = function() {
	while (this.resources.length > 0) {
		delete this[ this.resources.shift().getName() ];
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
Client.prototype.sendAsQueryParams = function(method) {
	return ['GET', 'OPTIONS'].indexOf(method) != -1;
};

/**
 * Add URL encoded parameters to URL.
 * Note that this method does not support object_list or hash_list layouts.
 * @method HaveAPI.Client#addParamsToQuery
 * @param {String} url
 * @param {String} namespace
 * @param {Object} params
 * @private
 */
Client.prototype.addParamsToQuery = function(url, namespace, params) {
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
};
