import { openRequest, sendRequest } from "./transport";
import type { HttpOptions, LegacyXMLHttpRequest } from "./types";

export interface Http {
  debug: number;
  request(opts: HttpOptions): void;
}
export interface HttpConstructor {
  new (debug?: number): Http;
  prototype: Http;
}

/**
 * @class Http
 * @memberof HaveAPI.Client
 */
export const Http = function Http(this: Http, debug: number) {
  this.debug = debug;
} as unknown as HttpConstructor;

/**
 * @callback HaveAPI.Client.Http~replyCallback
 * @param {Integer} status received HTTP status code
 * @param {Object} response received response
 */

/**
 * @method HaveAPI.Client.Http#request
 */
Http.prototype.request = function (opts) {
  if (this.debug > 5) console.log("Request to " + opts.method + " " + opts.url);

  var r = openRequest(opts);

  r.onreadystatechange = function () {
    var state = r.readyState;

    if (this.debug! > 6) console.log("Request state is " + state);

    if (state == 4 && opts.callback !== undefined) {
      var json = null;

      try {
        json = JSON.parse(r.responseText);
      } catch (e) {
        console.log("JSON.parse failed", e);
      }

      if (json) opts.callback(r.status, json);
      else opts.callback(false, undefined);
    }
  };

  sendRequest(r, opts);
};
