/**
 * Thrown when protocol error/incompatibility occurs.
 * @class ProtocolError
 * @memberof HaveAPI.Client.Exceptions
 */
Client.Exceptions.ProtocolError = function (msg) {
	this.name = 'ProtocolError';
	this.message = msg;
}

/**
 * Thrown when calling an action and some arguments are left unresolved.
 * @class UnresolvedArguments
 * @memberof HaveAPI.Client.Exceptions
 */
Client.Exceptions.UnresolvedArguments = function (action) {
	this.name = 'UnresolvedArguments';
	this.message = "Unable to execute action '"+ this.name +"': unresolved arguments";
}
