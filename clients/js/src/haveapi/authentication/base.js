/**
 * @class Base
 * @classdesc Base class for all authentication providers. They do not have to inherit
 *            it directly, but must implement all necessary methods.
 * @memberof HaveAPI.Client.Authentication
 */
Authentication.Base = function (client, opts, description){};

/**
 * Setup the authentication provider and call the callback.
 * @method HaveAPI.Client.Authentication.Base#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Base.prototype.setup = function(callback){};

/**
 * Logout, destroy all resources and call the callback.
 * @method HaveAPI.Client.Authentication.Base#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Base.prototype.logout = function(callback) {
	callback(this.client, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Base#credentials
 * @return {Object} credentials
 */
Authentication.Base.prototype.credentials = function(){};

/**
 * Returns an object with HTTP headers to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#headers
 * @return {Object} HTTP headers
 */
Authentication.Base.prototype.headers = function(){};

/**
 * Returns an object with query parameters to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#queryParameters
 * @return {Object} query parameters
 */
Authentication.Base.prototype.queryParameters = function(){};
