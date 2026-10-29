import type { Action } from "./action";
import type { Envelope, Meta, Values } from "./types";

export interface Response<T = unknown> {
  action: Action | undefined;
  envelope: Envelope;
  isOk(): boolean;
  response(): T | null | undefined;
  message(): string | null | undefined;
  meta(): Meta;
}
export interface ResponseConstructor {
  new <T = unknown>(action?: Action, response?: Envelope): Response<T>;
  prototype: Response;
}

/**
 * @class Response
 * @memberof HaveAPI.Client
 */
export const Response = function Response(
  this: Response,
  action?: Action,
  response?: Envelope,
) {
  this.action = action;
  this.envelope = response!;
} as unknown as ResponseConstructor;

/**
 * Returns true if the request was successful.
 * @method HaveAPI.Client.Response#isOk
 * @return {Boolean}
 */
Response.prototype.isOk = function () {
  return this.envelope.status;
};

/**
 * Returns the namespaced response if possible.
 * @method HaveAPI.Client.Response#response
 * @return {Object} response
 */
Response.prototype.response = function () {
  if (!this.action) return this.envelope.response;

  if (!this.envelope.response) return null;

  switch (this.action.layout("output")) {
    case "object":
    case "object_list":
    case "hash":
    case "hash_list":
      return (this.envelope.response as Values)[
        this.action.namespace("output")!
      ];

    default:
      return this.envelope.response;
  }
};

/**
 * Return the error message received from the API.
 * @method HaveAPI.Client.Response#message
 * @return {String}
 */
Response.prototype.message = function () {
  return this.envelope.message;
};

/**
 * Return the global meta data.
 * @method HaveAPI.Client.Response#meta
 * @return {Object}
 */
Response.prototype.meta = function () {
  var metaNs = this.action!.client.apiSettings!.meta.namespace;

  if (this.envelope.response && this.envelope.response.hasOwnProperty(metaNs))
    return (this.envelope.response as Values)[metaNs] as Meta;

  return {};
};
