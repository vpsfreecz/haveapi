import { Response } from './response';
import type { Action } from './action';
import type { ValidationErrors } from './types';

export interface LocalResponse extends Response {}
export interface LocalResponseConstructor {
	new(action: Action, status: boolean, message: string, errors: ValidationErrors): LocalResponse;
	prototype: LocalResponse;
}


/**
 * @class LocalResponse
 * @memberof HaveAPI.Client
 * @augments HaveAPI.Client.Response
 */
export const LocalResponse = function LocalResponse(this: LocalResponse, action: Action, status: boolean, message: string, errors: ValidationErrors) {
	this.action = action;
	this.envelope = {
		status: status,
		message: message,
		errors: errors,
	};
} as unknown as LocalResponseConstructor;

LocalResponse.prototype = new Response();
