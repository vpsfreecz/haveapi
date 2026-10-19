import { Authentication } from '../authentication';
import './base';
import { XMLHttpRequest } from '../xml_http_request';
import type { Provider, AuthenticationOptions } from '../authentication';
import type { Client, DoneCallback } from '../client';
import type { AuthenticationDescription } from '../types';

type AccessToken = NonNullable<AuthenticationOptions['access_token']>;
export interface OAuth2 extends Provider {
	client: Client;
	opts: AuthenticationOptions;
	description: AuthenticationDescription;
	access_token: AccessToken | null;
}
export interface OAuth2Constructor {
	new(client: Client, opts: AuthenticationOptions, description: AuthenticationDescription): OAuth2;
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
export const OAuth2 = function OAuth2(this: OAuth2, client: Client, opts: AuthenticationOptions, description: AuthenticationDescription) {
	this.client = client;
	this.opts = opts;
	this.description = description;

	/**
	 * @member {String} HaveAPI.Client.Authentication.OAuth2#access_token Access and refresh tokens
	 */
	this.access_token = null;
} as unknown as OAuth2Constructor;
Authentication.OAuth2 = OAuth2;
OAuth2.prototype = new Authentication.Base() as OAuth2;

/**
 * OAuth2 authentication options
 *
 * @typedef {Object} HaveAPI.Client.Authentication.OAuth2~Options
 * @property {HaveAPI.Client.Authentication.OAuth2~AccessTopen} access_token
 */

/**
 * Access token
 *
 * @typedef {Object} HaveAPI.Client.Authentication.OAuth2~AccessToken
 * @property {String} access_token
 * @property {String} refresh_token
 * @property {Integer} expires
 */

/**
 * @method HaveAPI.Client.Authentication.OAuth2#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
OAuth2.prototype.setup = function(callback?: DoneCallback) {
	if (this.opts.hasOwnProperty('access_token')) {
		this.access_token = this.opts.access_token!;

		if (callback !== undefined)
			callback(this.client, true);
	} else {
		throw this.client.translate('authentication.oauth2_access_token_required');
	}
};

/**
 * @method HaveAPI.Client.Authentication.OAuth2#headers
 */
OAuth2.prototype.headers = function() {
	var ret: Record<string, string> = {};

	// We send the token through the HaveAPI-speficic HTTP header, because
	// the Authorization header is not allowed by the server's CORS policy.
	ret[ this.description.http_header! ] = this.access_token!.access_token;

	return ret;
};

/**
 * @method HaveAPI.Client.Authentication.OAuth2#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
OAuth2.prototype.logout = function(callback: DoneCallback) {
	var http = new XMLHttpRequest();
	var that = this;
	var revokeUrl = this.client.oauth2Url(this.description.revoke_url!);

	http.open('POST', revokeUrl, true);
	http.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');

	var headers = this.client.requestHeaders({});
	for (var name in headers) {
		if (headers.hasOwnProperty(name))
			http.setRequestHeader(name, headers[name]);
	}

	http.onreadystatechange = function() {
		if (http.readyState == 4) {
			callback(that.client, http.status == 200);
		}
	}

	http.send("token=" + encodeURIComponent(this.access_token!.access_token));
};
