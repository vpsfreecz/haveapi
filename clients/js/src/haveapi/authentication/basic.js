/**
 * @class Basic
 * @classdesc Authentication provider for HTTP basic auth.
 *            Unfortunately, this provider probably won't work in most browsers
 *            because of their security considerations.
 * @memberof HaveAPI.Client.Authentication
 */
Authentication.Basic = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
};
Authentication.Basic.prototype = new Authentication.Base();

/**
 * @method HaveAPI.Client.Authentication.Basic#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Basic.prototype.setup = function(callback) {
	if(callback !== undefined)
		callback(this.client, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Basic#credentials
 * @return {Object} credentials
 */
Authentication.Basic.prototype.credentials = function() {
	return this.opts;
};
