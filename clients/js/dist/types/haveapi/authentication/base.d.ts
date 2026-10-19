import type { Provider, AuthenticationOptions } from '../authentication';
import type { Client } from '../client';
import type { AuthenticationDescription } from '../types';
export interface Base extends Provider {
}
export interface BaseConstructor {
    new (client?: Client, opts?: AuthenticationOptions, description?: AuthenticationDescription): Base;
    prototype: Base;
}
/**
 * @class Base
 * @classdesc Base class for all authentication providers. They do not have to inherit
 *            it directly, but must implement all necessary methods.
 * @memberof HaveAPI.Client.Authentication
 */
export declare const Base: BaseConstructor;
