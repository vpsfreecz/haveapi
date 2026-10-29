import { Authentication } from "../authentication";
import "./base";
import { Client } from "../client";
import type { Provider, AuthenticationOptions } from "../authentication";
import type { DoneCallback } from "../client";
import type { Action } from "../action";
import type { Resource } from "../resource";
import type { Response } from "../response";
import type {
  AuthenticationDescription,
  ParameterDescription,
  Values,
} from "../types";

interface TokenReply {
  token: string;
  valid_to?: string;
  complete: boolean;
  next_action: string;
}
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
  authenticationStep(
    action: string,
    input: Values,
    callback?: DoneCallback,
  ): void;
  renewToken(callback?: DoneCallback): void;
  getRequestCredentials(): string[];
  getCustomActionCredentials(
    action: string,
  ): Record<string, ParameterDescription>;
}
export interface TokenConstructor {
  new (
    client: Client,
    opts: AuthenticationOptions,
    description: AuthenticationDescription,
  ): Token;
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
export const Token = function Token(
  this: Token,
  client: Client,
  opts: AuthenticationOptions,
  description: AuthenticationDescription,
) {
  this.client = client;
  this.opts = opts;
  this.description = description;
  this.configured = false;

  /**
   * @member {String} HaveAPI.Client.Authentication.Token#token The token received from the API.
   */
  this.token = null;
} as unknown as TokenConstructor;
Authentication.Token = Token;
Token.prototype = new Authentication.Base() as Token;

/**
 * Token authentication options
 *
 * In addition to the options below, it accepts also input credentials
 * based on the API server the client is connected to, i.e. usually `user`
 * and `password`.
 * @typedef {Object} HaveAPI.Client.Authentication.Token~Options
 * @property {String} lifetime
 * @property {Integer} interval
 * @property {HaveAPI.Client.Authentication.Token~authenticationCallback} callback
 */

/**
 * This callback is invoked if the API server requires multi-step authentication
 * process. The function has to return input parameters for the next
 * authentication action, or invoke a callback passed as an argument.
 * @callback HaveAPI.Client.Authentication.Token~authenticationCallback
 * @param {String} action action name
 * @param {Object} params input parameters and their description
 * @param {HaveAPI.Client.Authentication.Token~continueCallback} cont
 * @return {Object} input parameters to send to the API
 * @return {null} the callback function will be invoked
 */

/**
 * @callback HaveAPI.Client.Authentication.Token~continueCallback
 * @param {Object} input input parameters to send to the API
 */

/**
 * @method HaveAPI.Client.Authentication.Token#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.setup = function (callback?: DoneCallback) {
  this.resource = new Client.Resource(
    this.client,
    null,
    "token",
    this.description.resources!.token,
    [],
  ) as Resource & Record<string, Action>;

  if (this.opts.hasOwnProperty("token")) {
    this.token = this.opts.token!;
    this.validTo = this.opts.validTo;
    this.configured = true;

    if (callback !== undefined) callback(this.client, true);
  } else {
    this.requestToken(callback);
  }
};

/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.requestToken = function (callback?: DoneCallback) {
  var that = this;
  var input: Values = {
    lifetime: this.opts.lifetime || "renewable_auto",
  };

  if (this.opts.interval !== undefined) input.interval = this.opts.interval;

  this.getRequestCredentials().forEach(function (param) {
    if (that.opts[param] !== undefined) input[param] = that.opts[param];
  });

  this.authenticationStep("request", input, callback);
};

/**
 * @method HaveAPI.Client.Authentication.Token#authenticationStep
 * @param {String} action action name
 * @param {Object} input input parameters
 * @param {HaveAPI.Client~doneCallback} callback
 * @private
 */
Token.prototype.authenticationStep = function (
  action: string,
  input: Values,
  callback?: DoneCallback,
) {
  var that = this;

  this.resource[action](input, function (c, response) {
    if (response.isOk()) {
      var t = (response as Response<TokenReply>).response()!;

      if (t.complete) {
        that.token = t.token;
        that.validTo = t.valid_to;
        that.configured = true;

        if (callback !== undefined) callback(that.client, true);
      } else {
        if (that.opts.callback === undefined)
          throw that.client.translate("authentication.mfa_required");

        var cont = function (input: Values) {
          that.authenticationStep(
            t.next_action,
            Object.assign({}, input, { token: t.token }),
            callback,
          );
        };

        var ret = that.opts.callback(
          t.next_action,
          that.getCustomActionCredentials(t.next_action),
          cont,
        );

        if (typeof ret === "object" && ret !== null) cont(ret);
      }
    } else {
      if (callback !== undefined) callback(that.client, false);
    }
  });
};
/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.renewToken = function (callback?: DoneCallback) {
  var that = this;

  this.resource.renew(function (c, response) {
    if (response.isOk()) {
      var t = (response as Response<TokenReply>).response()!;

      that.validTo = t.valid_to;

      if (callback !== undefined) callback(that.client, true);
    } else {
      if (callback !== undefined) callback(that.client, false);
    }
  });
};

/**
 * @method HaveAPI.Client.Authentication.Token#headers
 */
Token.prototype.headers = function () {
  if (!this.configured) return;

  var ret: Record<string, string> = {};
  ret[this.description.http_header!] = this.token!;

  return ret;
};

/**
 * @method HaveAPI.Client.Authentication.Token#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.logout = function (callback: DoneCallback) {
  this.resource.revoke(null, function (this: unknown, c, reply) {
    // Keep the callback's original unbound receiver semantics.
    callback((this as unknown as { client: Client }).client, reply.isOk());
  });
};

/**
 * Return names of parameters used as credentials for custom authentication
 * @method HaveAPI.Client.Authentication.Token#getRequestCredentials
 * @private
 * @return {Array}
 */
Token.prototype.getRequestCredentials = function () {
  var ret = [];

  for (var param in this.resource.request.description.input!.parameters) {
    if (param != "lifetime" && param != "interval") ret.push(param);
  }

  return ret;
};

/**
 * Return names of parameters used as credentials for custom authentication
 * action
 * @method HaveAPI.Client.Authentication.Token#getCustomActionCredentials
 * @private
 * @return {Array}
 */
Token.prototype.getCustomActionCredentials = function (action) {
  var ret: Record<string, ParameterDescription> = {};
  var desc = this.resource[action].description.input!.parameters;

  for (var param in desc) {
    if (param != "token") ret[param] = desc[param];
  }

  return ret;
};
