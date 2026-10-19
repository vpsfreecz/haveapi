import './base';
import type { Provider, AuthenticationOptions } from '../authentication';
import type { Client } from '../client';
import type { AuthenticationDescription } from '../types';
type AccessToken = NonNullable<AuthenticationOptions['access_token']>;
export interface OAuth2 extends Provider {
    client: Client;
    opts: AuthenticationOptions;
    description: AuthenticationDescription;
    access_token: AccessToken | null;
}
export interface OAuth2Constructor {
    new (client: Client, opts: AuthenticationOptions, description: AuthenticationDescription): OAuth2;
    prototype: OAuth2;
}
/**
 * @class OAuth2
 * @classdesc OAuth2 authentication provider.
 *            This provider can only use existing access tokens, it does not have
 *            the ability to request authorization on its own.
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Authentication.OAuth2~Options} opts
 * @param {Object} description
 * @memberof HaveAPI.Client.Authentication
 */
export declare const OAuth2: OAuth2Constructor;
export {};
