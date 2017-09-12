/**
 * @class Response
 * @memberof HaveAPI.Client
 */
function Response (action, response) {
	this.action = action;
	this.envelope = response;
};

/**
 * Returns true if the request was successful.
 * @method HaveAPI.Client.Response#isOk
 * @return {Boolean}
 */
Response.prototype.isOk = function() {
	return this.envelope.status;
};

/**
 * Returns the namespaced response if possible.
 * @method HaveAPI.Client.Response#response
 * @return {Object} response
 */
Response.prototype.response = function() {
	if(!this.action)
		return this.envelope.response;

        if (!this.envelope.response)
            return null;

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
Response.prototype.message = function() {
	return this.envelope.message;
};

/**
 * Return the global meta data.
 * @method HaveAPI.Client.Response#meta
 * @return {Object}
 */
Response.prototype.meta = function() {
	var metaNs = this.action.client.apiSettings.meta.namespace;

	if (this.envelope.response && this.envelope.response.hasOwnProperty(metaNs))
		return this.envelope.response[metaNs];

	return {};
};

