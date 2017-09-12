/**
 * @class LocalResponse
 * @memberof HaveAPI.Client
 * @augments HaveAPI.Client.Response
 */
function LocalResponse (action, status, message, errors) {
	this.action = action;
	this.envelope = {
		status: status,
		message: message,
		errors: errors,
	};
};

LocalResponse.prototype = new Response();
