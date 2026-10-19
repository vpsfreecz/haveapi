import type { Client, DoneCallback } from './client';
import type { AuthenticationDescription, Credentials, HeaderMap, Values } from './types';
import type { BaseConstructor } from './authentication/base';
import type { BasicConstructor } from './authentication/basic';
import type { OAuth2Constructor } from './authentication/oauth2';
import type { TokenConstructor } from './authentication/token';
import { legacyGlobals } from './legacy_globals';

export interface AuthenticationOptions extends Values {
	user?: string;
	password?: string;
	token?: string;
	validTo?: string | Date;
	lifetime?: string;
	interval?: number;
	access_token?: {access_token: string; refresh_token?: string; expires?: number};
	callback?: (action: string, params: Values, cont: (input: Values) => void) => Values | null | void;
}
export interface Provider {
	client?: Client;
	setup(callback?: DoneCallback): void;
	logout(callback: DoneCallback): void;
	credentials(): Credentials | undefined;
	headers(): HeaderMap | undefined;
	queryParameters(): Values | undefined;
}
export interface ProviderConstructor {
	new(client: Client, opts: AuthenticationOptions, description: AuthenticationDescription): Provider;
}
export interface AuthenticationRegistry {
	providers: Record<string, ProviderConstructor>;
	Base: BaseConstructor;
	Basic: BasicConstructor;
	OAuth2: OAuth2Constructor;
	Token: TokenConstructor;
	registerProvider(name: string, obj: ProviderConstructor): void;
}

/**
 * @namespace Authentication
 * @memberof HaveAPI.Client
 */
legacyGlobals.Authentication = {
	/**
	 * @member {Array} providers An array of registered authentication providers.
	 * @memberof HaveAPI.Client.Authentication
	 */
	providers: {},

	/**
	 * Register authentication providers using this function.
	 * @func registerProvider
	 * @memberof HaveAPI.Client.Authentication
	 * @param {string} name must be the same name as in announced by the API
	 * @param {Object} provider class
	 */
	registerProvider: function(name: string, obj: ProviderConstructor) {
		legacyGlobals.Authentication.providers[name] = obj;
	}
} as AuthenticationRegistry;

const authenticationRegistry = legacyGlobals.Authentication;
export { authenticationRegistry as Authentication };
