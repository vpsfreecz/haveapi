import './base';
import type { Provider, AuthenticationOptions } from '../authentication';
import type { Client } from '../client';
import type { AuthenticationDescription } from '../types';
export interface Basic extends Provider {
    client: Client;
    opts: AuthenticationOptions;
}
export interface BasicConstructor {
    new (client: Client, opts: AuthenticationOptions, description?: AuthenticationDescription): Basic;
    prototype: Basic;
}
/**
 * @class Basic
 * @classdesc Authentication provider for HTTP basic auth.
 *            Unfortunately, this provider probably won't work in most browsers
 *            because of their security considerations.
 * @memberof HaveAPI.Client.Authentication
 */
export declare const Basic: BasicConstructor;
