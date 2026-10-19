import './base';
import { Client } from '../client';
import type { Provider, AuthenticationOptions } from '../authentication';
import type { DoneCallback } from '../client';
import type { Action } from '../action';
import type { Resource } from '../resource';
import type { AuthenticationDescription, ParameterDescription, Values } from '../types';
export interface Token extends Provider {
    client: Client;
    opts: AuthenticationOptions;
    description: AuthenticationDescription;
    configured: boolean;
    token: string | null;
    validTo?: string | Date;
    /** Dynamic token actions are supplied by the authentication description. */
    resource: Resource & Record<string, Action>;
    requestToken(callback?: DoneCallback): void;
    authenticationStep(action: string, input: Values, callback?: DoneCallback): void;
    renewToken(callback?: DoneCallback): void;
    getRequestCredentials(): string[];
    getCustomActionCredentials(action: string): Record<string, ParameterDescription>;
}
export interface TokenConstructor {
    new (client: Client, opts: AuthenticationOptions, description: AuthenticationDescription): Token;
    prototype: Token;
}
/**
 * @class Token
 * @classdesc Token authentication provider.
 * @memberof HaveAPI.Client.Authentication
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Authentication.Token~Options} opts
 * @param {Object} description
 */
export declare const Token: TokenConstructor;
