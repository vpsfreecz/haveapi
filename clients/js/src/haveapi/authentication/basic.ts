import { Authentication } from '../authentication';
import './base';
import type { Provider, AuthenticationOptions } from '../authentication';
import type { Client, DoneCallback } from '../client';
import type { AuthenticationDescription } from '../types';

export interface Basic extends Provider {
	client: Client;
	opts: AuthenticationOptions;
}
export interface BasicConstructor {
	new(client: Client, opts: AuthenticationOptions, description?: AuthenticationDescription): Basic;
	prototype: Basic;
}

/**
 * @class Basic
 * @classdesc Authentication provider for HTTP basic auth.
 *            Unfortunately, this provider probably won't work in most browsers
 *            because of their security considerations.
 * @memberof HaveAPI.Client.Authentication
 */
export const Basic = function Basic(this: Basic, client: Client, opts: AuthenticationOptions, description?: AuthenticationDescription) {
	this.client = client;
	this.opts = opts;
} as unknown as BasicConstructor;
Authentication.Basic = Basic;
Basic.prototype = new Authentication.Base() as Basic;

/**
 * @method HaveAPI.Client.Authentication.Basic#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Basic.prototype.setup = function(callback?: DoneCallback) {
	if(callback !== undefined)
		callback(this.client, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Basic#credentials
 * @return {Object} credentials
 */
Basic.prototype.credentials = function() {
	return this.opts;
};
