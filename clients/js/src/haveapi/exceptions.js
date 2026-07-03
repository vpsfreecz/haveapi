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
	this.message = action.client.translate('errors.unresolved_arguments', {
		action: action.name
	});
}

/**
 * Thrown when trying to cancel an action that cannot be cancelled.
 * @class UncancelableAction
 * @memberof HaveAPI.Client.Exceptions
 */
Client.Exceptions.UncancelableAction = function (stateId, client) {
	this.name = 'UncancelableAction';
	this.message = client.translate('errors.uncancelable_action', {id: stateId});
}
