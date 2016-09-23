/**
 * @class Token
 * @classdesc Token authentication provider.
 * @memberof HaveAPI.Client.Authentication
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
