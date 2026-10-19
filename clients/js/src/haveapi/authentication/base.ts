import { Authentication } from '../authentication';
import type { Provider, AuthenticationOptions } from '../authentication';
import type { Client, DoneCallback } from '../client';
import type { AuthenticationDescription } from '../types';

export interface Base extends Provider {}
export interface BaseConstructor {
	new(client?: Client, opts?: AuthenticationOptions, description?: AuthenticationDescription): Base;
	prototype: Base;
}

/**
 * @class Base
 * @classdesc Base class for all authentication providers. They do not have to inherit
 *            it directly, but must implement all necessary methods.
 * @memberof HaveAPI.Client.Authentication
 */
export const Base = function Base(this: Base, client?: Client, opts?: AuthenticationOptions, description?: AuthenticationDescription){} as unknown as BaseConstructor;
Authentication.Base = Base;

/**
 * Setup the authentication provider and call the callback.
 * @method HaveAPI.Client.Authentication.Base#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Base.prototype.setup = function(callback?: DoneCallback){};

/**
 * Logout, destroy all resources and call the callback.
 * @method HaveAPI.Client.Authentication.Base#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Base.prototype.logout = function(callback: DoneCallback) {
	callback(this.client!, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Base#credentials
 * @return {Object} credentials
 */
Base.prototype.credentials = function(): undefined {};

/**
 * Returns an object with HTTP headers to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#headers
 * @return {Object} HTTP headers
 */
Base.prototype.headers = function(): undefined {};

/**
 * Returns an object with query parameters to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#queryParameters
 * @return {Object} query parameters
 */
Base.prototype.queryParameters = function(): undefined {};
