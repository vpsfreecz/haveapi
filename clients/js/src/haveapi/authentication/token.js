/**
 * @class Token
 * @classdesc Token authentication provider.
 * @memberof HaveAPI.Client.Authentication
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Authentication.Token~Options} opts
 * @param {Object} description
 */
Authentication.Token = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
	this.description = description;
	this.configured = false;

	/**
	 * @member {String} HaveAPI.Client.Authentication.Token#token The token received from the API.
	 */
	this.token = null;
};
Authentication.Token.prototype = new Authentication.Base();

/**
 * Token authentication options
 *
 * In addition to the options below, it accepts also input credentials
 * based on the API server the client is connected to, i.e. usually `user`
 * and `password`.
 * @typedef {Object} HaveAPI.Client.Authentication.Token~Options
 * @property {String} lifetime
 * @property {Integer} interval
 * @property {HaveAPI.Client.Authentication.Token~authenticationCallback} callback
 */

/**
 * This callback is invoked if the API server requires multi-step authentication
 * process. The function has to return input parameters for the next
 * authentication action, or invoke a callback passed as an argument.
 * @callback HaveAPI.Client.Authentication.Token~authenticationCallback
 * @param {String} action action name
 * @param {Object} params input parameters and their description
 * @param {HaveAPI.Client.Authentication.Token~continueCallback} cont
 * @return {Object} input parameters to send to the API
 * @return {null} the callback function will be invoked
 */

/**
 * @callback HaveAPI.Client.Authentication.Token~continueCallback
 * @param {Object} input input parameters to send to the API
 */

/**
 * @method HaveAPI.Client.Authentication.Token#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Token.prototype.setup = function(callback) {
	this.resource = new Client.Resource(
		this.client,
		null,
		'token',
		this.description.resources.token,
		[]
	);

	if (this.opts.hasOwnProperty('token')) {
		this.token = this.opts.token;
		this.validTo = this.opts.validTo;
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
Authentication.Token.prototype.requestToken = function(callback) {
	var that = this;
	var input = {
		lifetime: this.opts.lifetime || 'renewable_auto'
	};

	if (this.opts.interval !== undefined)
		input.interval = this.opts.interval;

	this.getRequestCredentials().forEach(function (param) {
		if (that.opts[param] !== undefined)
			input[param] = that.opts[param];
	});

	this.authenticationStep('request', input, callback);
};

/**
 * @method HaveAPI.Client.Authentication.Token#authenticationStep
 * @param {String} action action name
 * @param {Object} input input parameters
 * @param {HaveAPI.Client~doneCallback} callback
 * @private
 */
Authentication.Token.prototype.authenticationStep = function(action, input, callback) {
	var that = this;

	this.resource[action](input, function(c, response) {
		if (response.isOk()) {
			var t = response.response();

			if (t.complete) {
				that.token = t.token;
				that.validTo = t.valid_to;
				that.configured = true;

				if (callback !== undefined)
					callback(that.client, true);
			} else {
				if (that.opts.callback === undefined)
					throw "implement multi-factor authentication";

				var cont = function (input) {
					that.authenticationStep(
						t.next_action,
						Object.assign({}, input, {token: t.token}),
						callback
					);
				}

				var ret = that.opts.callback(
					t.next_action,
					that.getCustomActionCredentials(t.next_action),
					cont
				);

				if (typeof ret === 'object' && ret !== null)
					cont(ret);
			}

		} else {
			if (callback !== undefined)
				callback(that.client, false);
		}
	});
};
/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Token.prototype.renewToken = function(callback) {
	var that = this;

	this.resource.renew(function(c, response) {
		if (response.isOk()) {
			var t = response.response();

			that.validTo = t.valid_to;

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
Authentication.Token.prototype.headers = function(){
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
Authentication.Token.prototype.logout = function(callback) {
	this.resource.revoke(null, function(c, reply) {
		callback(this.client, reply.isOk());
	});
};

/**
 * Return names of parameters used as credentials for custom authentication
 * @method HaveAPI.Client.Authentication.Token#getRequestCredentials
 * @private
 * @return {Array}
 */
Authentication.Token.prototype.getRequestCredentials = function() {
	var ret = [];

	for (var param in this.resource.request.description.input.parameters) {
		if (param != "lifetime" && param != "interval")
			ret.push(param);
	}

	return ret;
}

/**
 * Return names of parameters used as credentials for custom authentication
 * action
 * @method HaveAPI.Client.Authentication.Token#getCustomActionCredentials
 * @private
 * @return {Array}
 */
Authentication.Token.prototype.getCustomActionCredentials = function(action) {
	var ret = {};
	var desc = this.resource[action].description.input.parameters;

	for (var param in desc) {
		if (param != "token")
			ret[param] = desc[param];
	}

	return ret;
}
