/**
 * @class OAuth2
 * @classdesc OAuth2 authentication provider.
 *            This provider can only use existing access tokens, it does not have
 *            the ability to request authorization on its own.
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Authentication.OAuth2~Options} opts
 * @param {Object} description
 * @memberof HaveAPI.Client.Authentication
 */
Authentication.OAuth2 = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
	this.description = description;

	/**
	 * @member {String} HaveAPI.Client.Authentication.OAuth2#access_token Access and refresh tokens
	 */
	this.access_token = null;
};
Authentication.OAuth2.prototype = new Authentication.Base();

/**
 * OAuth2 authentication options
 *
 * @typedef {Object} HaveAPI.Client.Authentication.OAuth2~Options
 * @property {HaveAPI.Client.Authentication.OAuth2~AccessTopen} access_token
 */

/**
 * Access token
 *
 * @typedef {Object} HaveAPI.Client.Authentication.OAuth2~AccessToken
 * @property {String} access_token
 * @property {String} refresh_token
 * @property {Integer} expires
 */

/**
 * @method HaveAPI.Client.Authentication.OAuth2#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.OAuth2.prototype.setup = function(callback) {
	if (this.opts.hasOwnProperty('access_token')) {
		this.access_token = this.opts.access_token;

		if (callback !== undefined)
			callback(this.client, true);
	} else {
		throw "Option access_token must be provided";
	}
};

/**
 * @method HaveAPI.Client.Authentication.OAuth2#headers
 */
Authentication.OAuth2.prototype.headers = function() {
	var ret = {};

	// We send the token through the HaveAPI-speficic HTTP header, because
	// the Authorization header is not allowed by the server's CORS policy.
	ret[ this.description.http_header ] = this.access_token.access_token;

	return ret;
};

/**
 * @method HaveAPI.Client.Authentication.OAuth2#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.OAuth2.prototype.logout = function(callback) {
	var http = new XMLHttpRequest();
	var that = this;

	http.open('POST', this.client._private.url + this.description.revoke_path, true);
	http.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');

	http.onreadystatechange = function() {
		if (http.readyState == 4) {
			callback(that.client, http.status == 200);
		}
	}

	http.send("token=" + this.access_token.access_token);
};
