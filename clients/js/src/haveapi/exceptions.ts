import { Client } from './client';
import type { Action } from './action';

export interface ProtocolError {
	name: string;
	message: string;
}
export interface UnresolvedArguments extends ProtocolError {}
export interface UncancelableAction extends ProtocolError {}
export interface Exceptions {
	ProtocolError: {new(msg: string): ProtocolError};
	UnresolvedArguments: {new(action: Action): UnresolvedArguments};
	UncancelableAction: {new(stateId: string | number, client: Client): UncancelableAction};
}

/** These intentionally retain the legacy plain exception prototypes. */
Client.Exceptions.ProtocolError = function(this: ProtocolError, msg: string) {
	this.name = 'ProtocolError';
	this.message = msg;
} as unknown as Exceptions['ProtocolError'];

Client.Exceptions.UnresolvedArguments = function(this: UnresolvedArguments, action: Action) {
	this.name = 'UnresolvedArguments';
	this.message = action.client.translate('errors.unresolved_arguments', {
		action: action.name
	});
} as unknown as Exceptions['UnresolvedArguments'];

Client.Exceptions.UncancelableAction = function(this: UncancelableAction, stateId: string | number, client: Client) {
	this.name = 'UncancelableAction';
	this.message = client.translate('errors.uncancelable_action', {id: stateId});
} as unknown as Exceptions['UncancelableAction'];
