import {
  normalizeTrustedOrigins,
  resolveApiUrl,
  addParamsToQuery,
} from "./protocol";
import "./authentication";
import { legacyGlobals } from "./legacy_globals";
import { I18n } from "./i18n";
import type {
  Provider,
  AuthenticationOptions,
  AuthenticationRegistry,
} from "./authentication";
import type {
  Action,
  ActionConstructor,
  ActionCall,
  ActionReply,
} from "./action";
import type { ActionStateConstructor } from "./action_state";
import type { BaseResource, BaseResourceConstructor } from "./base_resource";
import type { Resource, ResourceConstructor } from "./resource";
import type { ResourceInstanceConstructor } from "./resource_instance";
import type { ResourceInstanceListConstructor } from "./resource_instance_list";
import type { Response, ResponseConstructor } from "./response";
import type { LocalResponseConstructor } from "./local_response";
import type { Hooks, HooksConstructor } from "./hooks";
import type { Http, HttpConstructor } from "./http";
import type { Exceptions } from "./exceptions";
import type {
  ClientOptions,
  Description,
  HeaderMap,
  Language,
  Params,
  ParameterDescription,
  Values,
  Versions,
  Envelope,
} from "./types";

export type DoneCallback = (client: Client, status: boolean) => void;
export type VersionsCallback = (
  client: Client,
  status: boolean,
  versions: Versions | null,
) => void;
export type CompatibleCallback = (
  compatible: "compatible" | "imperfect" | false,
) => void;
export type DescriptionCallback = (
  status: boolean,
  extract: () => unknown,
) => void;
export interface ClientInvocationOptions<
  T = ActionReply,
> extends ActionCall<T> {
  path?: string;
  /** Retained internal spelling used by the legacy callback guard. */
  onStateUpdate?: unknown;
}
export interface ClientState {
  url: string;
  version: string | number | null;
  description: Description | null;
  attachedResourceNames: Record<string, boolean>;
  debug: number;
  oauth2TrustedOrigins: string[];
  language: Language;
  languageHeader: string;
  hooks?: Hooks;
  http?: Http;
  protocolVersion?: string;
}
export interface Client {
  _private: ClientState;
  apiSettings: { meta: { namespace: string } } | null;
  resources: Resource[];
  authProvider: Provider;
  sameOriginUrl(
    url: string,
    opts?: { actionPath?: boolean; trustedOrigins?: string[] },
  ): string;
  oauth2Url(url: string): string;
  setLanguage(language: Language): void;
  setLanguageHeader(header: string): void;
  translate(key: string, values?: Values): string;
  languageHeaders(): HeaderMap;
  requestHeaders(headers?: HeaderMap): HeaderMap;
  setup(callback: DoneCallback): void;
  useDescription(description: Description): void;
  availableVersions(callback: VersionsCallback): void;
  isCompatible(callback: CompatibleCallback): void;
  fetchDescription(callback: DescriptionCallback, path?: string): void;
  attachResources(): void;
  authenticate(
    method: string,
    opts: AuthenticationOptions,
    callback: DoneCallback,
    reset?: boolean,
  ): void;
  logout(callback?: DoneCallback): void;
  directInvoke(action: Action, opts: ClientInvocationOptions<Response>): void;
  invoke(action: Action, opts: ClientInvocationOptions): void;
  after(event: string, callback: DoneCallback): void;
  createSettings(): void;
  destroyResources(): void;
  sendAsQueryParams(method: string): boolean;
  addParamsToQuery(
    url: string,
    namespace: string | null,
    params?: Params,
    paramDesc?: Record<string, ParameterDescription> | null,
  ): string;
}
export interface ClientConstructor {
  new (url: string, opts?: ClientOptions): Client;
  prototype: Client;
  Version: string;
  ProtocolVersion: string;
  unsafeAttachmentNames: Record<string, boolean>;
  Exceptions: Exceptions;
  hasOwn(obj: unknown, prop: PropertyKey): boolean;
  canAttachDescriptionMember(
    target: object,
    name: unknown,
    reservedNames?: Record<string, boolean>,
  ): boolean;
  attachDescriptionMember(
    target: object,
    name: string,
    value: unknown,
    reservedNames?: Record<string, boolean>,
  ): boolean;
  findResource(
    root: { resources: Resource[] },
    resourcePath: string[],
  ): Resource;
  findAction(resource: BaseResource, name: string): Action;
  normalizeTrustedOrigins(origins?: string | string[] | null): string[];
  Action: ActionConstructor;
  ActionState: ActionStateConstructor;
  Authentication: AuthenticationRegistry;
  BaseResource: BaseResourceConstructor;
  Hooks: HooksConstructor;
  Http: HttpConstructor;
  Resource: ResourceConstructor;
  ResourceInstance: ResourceInstanceConstructor;
  ResourceInstanceList: ResourceInstanceListConstructor;
  Response: ResponseConstructor;
  LocalResponse: LocalResponseConstructor;
}

/**
 * Create a new client for the API.
 * @class Client
 * @memberof HaveAPI
 * @param {string} url base URL to the API
 * @param {Object} opts
 */
export const Client = function Client(
  this: Client,
  url: string,
  opts?: ClientOptions,
) {
  opts = opts || {};
  var oauth2TrustedOrigins =
    opts.oauth2TrustedOrigins !== undefined
      ? opts.oauth2TrustedOrigins
      : opts.oauth2_trusted_origins;

  while (url.length > 0) {
    if (url[url.length - 1] == "/") url = url.substr(0, url.length - 1);
    else break;
  }

  /**
   * @member {Object} HaveAPI.Client#_private
   * @protected
   */
  this._private = {
    url: url,
    version:
      opts !== undefined && opts.version !== undefined ? opts.version : null,
    description: null,
    attachedResourceNames: Object.create(null),
    debug: opts !== undefined && opts.debug !== undefined ? opts.debug : 0,
    oauth2TrustedOrigins: (
      Client as unknown as ClientConstructor
    ).normalizeTrustedOrigins(oauth2TrustedOrigins),
    language: opts.language !== undefined ? opts.language : null,
    languageHeader:
      opts.languageHeader !== undefined
        ? opts.languageHeader
        : opts.language_header || I18n.DEFAULT_LANGUAGE_HEADER,
  };
  I18n.requestHeaders(this._private.language, this._private.languageHeader);

  this._private.hooks = new (Client as unknown as ClientConstructor).Hooks(
    this._private.debug,
  );
  this._private.http = new (Client as unknown as ClientConstructor).Http(
    this._private.debug,
  );

  /**
   * @member {Object} HaveAPI.Client#apiSettings An object containg API settings.
   */
  this.apiSettings = null;

  /**
   * @member {Array} HaveAPI.Client#resources A list of top-level resources attached to the client.
   */
  this.resources = [];

  /**
   * @member {Object} HaveAPI.Client#authProvider Selected authentication provider.
   */
  this.authProvider = new (
    Client as unknown as ClientConstructor
  ).Authentication.Base();
} as unknown as ClientConstructor;

/** @constant HaveAPI.Client.Version */
Client.Version = "0.32.0";

/** @constant HaveAPI.Client.ProtocolVersion */
Client.ProtocolVersion = "2.0";

Client.unsafeAttachmentNames = Object.create(null);
Client.unsafeAttachmentNames["__proto__"] = true;
Client.unsafeAttachmentNames["prototype"] = true;
Client.unsafeAttachmentNames["constructor"] = true;

/**
 * @namespace Exceptions
 * @memberof HaveAPI.Client
 */
Client.Exceptions = {} as Exceptions;

Client.hasOwn = function (obj, prop) {
  return Object.prototype.hasOwnProperty.call(obj, prop);
};

Client.canAttachDescriptionMember = function (target, name, reservedNames) {
  if (typeof name !== "string") return false;

  if (Client.hasOwn(Client.unsafeAttachmentNames, name)) return false;

  if (reservedNames && Client.hasOwn(reservedNames, name)) return false;

  return !(name in target);
};

Client.attachDescriptionMember = function (target, name, value, reservedNames) {
  if (!Client.canAttachDescriptionMember(target, name, reservedNames))
    return false;

  (target as Record<string, unknown>)[name] = value;
  return true;
};

Client.findResource = function (root, resourcePath) {
  var current: { resources: Resource[] } = root;
  var path = [];

  for (var i = 0; i < resourcePath.length; i++) {
    var name = resourcePath[i];
    var found = null;

    path.push(name);

    for (var j = 0; j < current.resources.length; j++) {
      if (current.resources[j].getName() === name) {
        found = current.resources[j];
        break;
      }
    }

    if (found === null) {
      throw new Client.Exceptions.ProtocolError(
        "Associated resource '" + path.join(".") + "' not found",
      );
    }

    current = found;
  }

  return current as Resource;
};

Client.normalizeTrustedOrigins = function (origins) {
  return normalizeTrustedOrigins(
    origins,
    (message) => new Client.Exceptions.ProtocolError(message),
  );
};

/** Look up canonical names and unambiguous aliases without direct properties. */
Client.findAction = function (resource, name) {
  var index = resource._private.actionIndex;
  if (!index || !Client.hasOwn(index, name))
    throw new Client.Exceptions.ProtocolError(
      "Action '" + name + "' not found or ambiguous",
    );
  return index[name];
};

/**
 * Resolve a URL from an API description and require it to stay on the
 * configured API origin.
 * @method HaveAPI.Client#sameOriginUrl
 * @param {String} url URL or path to resolve
 * @param {Object} opts
 * @return {String} absolute URL
 * @private
 */
Client.prototype.sameOriginUrl = function (url, opts) {
  return resolveApiUrl(
    this._private.url,
    url,
    opts,
    (message) => new Client.Exceptions.ProtocolError(message),
  );
};

Client.prototype.oauth2Url = function (url) {
  return this.sameOriginUrl(url, {
    trustedOrigins: this._private.oauth2TrustedOrigins,
  });
};

/**
 * Set the language sent to the API server.
 * @method HaveAPI.Client#setLanguage
 * @param {String} language value for Accept-Language
 */
Client.prototype.setLanguage = function (language) {
  I18n.requestHeaders(language, this._private.languageHeader);
  this._private.language = language;
};

/**
 * Set the language HTTP header name.
 * @method HaveAPI.Client#setLanguageHeader
 * @param {String} header HTTP header name
 */
Client.prototype.setLanguageHeader = function (header) {
  I18n.assertHeaderName(header);
  this._private.languageHeader = header;
};

Client.prototype.translate = function (key, values) {
  return I18n.translate(this._private.language, key, values);
};

Client.prototype.languageHeaders = function () {
  return I18n.requestHeaders(
    this._private.language,
    this._private.languageHeader,
  );
};

Client.prototype.requestHeaders = function (headers) {
  var ret: HeaderMap = {};
  var languageHeaders = this.languageHeaders();

  headers = headers || {};

  for (var name in headers) {
    if (headers.hasOwnProperty(name)) ret[name] = headers[name];
  }

  for (var langName in languageHeaders) {
    if (languageHeaders.hasOwnProperty(langName))
      ret[langName] = languageHeaders[langName];
  }

  return ret;
};

/**
 * @callback HaveAPI.Client~doneCallback
 * @param {HaveAPI.Client} client
 * @param {Boolean} status true if the task was successful
 */

/**
 * @callback HaveAPI.Client~replyCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Response} response
 */

/**
 * @callback HaveAPI.Client~versionsCallback
 * @param {HaveAPI.Client} client
 * @param {Boolean} status
 * @param {Object} versions
 */

/**
 * @callback HaveAPI.Client~actionStateCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Response} response
 * @param {HaveAPI.Client.ActionState} state
 */

/**
 * Action call parameters
 * @typedef {Object} HaveAPI.Client~ActionCall
 * @property {Object} params - Input parameters
 * @property {Object} meta - Input meta parameters
 * @property {Boolean} block
 * @property {Integer} blockInterval
 * @property {Integer} blockUpdateIn
 * @property {HaveAPI.Client~replyCallback} onReply - called when the API responds
 * @property {HaveAPI.Client~actionStateCallback} onStateChange - called when the
 *                                                                action's state changes
 * @property {HaveAPI.Client~replyCallback} onDone - called when the blocking action finishes
 */

/**
 * Setup resources and actions as properties and functions.
 * @method HaveAPI.Client#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.setup = function (callback) {
  var that = this;

  this.fetchDescription(function (status, extract) {
    var desc = null;

    try {
      desc = (extract as unknown as { call(): unknown }).call();
    } catch (e) {
      return callback(that, false);
    }

    that._private.description = (
      extract as unknown as { call(): unknown }
    ).call() as Description;
    that.createSettings();
    that.attachResources();

    callback(that, true);
    that._private.hooks!.invoke("after", "setup", that, true);
  });
};

/**
 * Provide the description and setup the client without asking the API.
 * @method HaveAPI.Client#useDescription
 * @param {Object} description
 */
Client.prototype.useDescription = function (description) {
  this._private.description = description;
  this.createSettings();
  this.attachResources();
};

/**
 * Call a callback with an object with list of available versions
 * and the default one.
 * @method HaveAPI.Client#availableVersions
 * @param {HaveAPI.Client~versionsCallback} callback
 */
Client.prototype.availableVersions = function (callback) {
  var that = this;

  this.fetchDescription(function (status, extract) {
    var versions = null;

    try {
      versions = (extract as unknown as { call(): unknown }).call() as Versions;
    } catch (e) {}

    callback(that, status && !(versions === null), versions);
  }, "/?describe=versions");
};

/**
 * @callback HaveAPI.Client~isCompatibleCallback
 * @param {mixed} compatible 'compatible', 'imperfect' or false
 */

/**
 * @method HaveAPI.Client#isCompatible
 * @param {HaveAPI.Client~isCompatibleCallback}
 */
Client.prototype.isCompatible = function (callback) {
  var that = this;

  this.fetchDescription(function (status, extract) {
    try {
      (extract as unknown as { call(): unknown }).call();

      if (that._private.protocolVersion == Client.ProtocolVersion)
        callback("compatible");
      else callback("imperfect");
    } catch (e) {
      if (e instanceof Client.Exceptions.ProtocolError) callback(false);
      else throw e;
    }
  }, "/?describe=versions");
};

/**
 * @callback HaveAPI.Client~descriptionCallback
 * @param {Boolean} status true if the description was successfuly fetched
 * @param {function} extract function that attempts to return the description
 */

/**
 * Fetch the description from the API.
 * @method HaveAPI.Client#fetchDescription
 * @private
 * @param {HaveAPI.Client.Http~descriptionCallback} callback
 * @param {String} path server path to query for
 */
Client.prototype.fetchDescription = function (callback, path) {
  var that = this;
  var url = this._private.url;

  if (path === undefined)
    url += this._private.version
      ? "/v" + this._private.version + "/"
      : "/?describe=default";
  else url += path;

  this._private.http!.request({
    method: "OPTIONS",
    url: url,
    credentials: this.authProvider.credentials(),
    headers: this.requestHeaders(this.authProvider.headers()),
    queryParameters: this.authProvider.queryParameters(),
    callback: function (status, response) {
      callback(status == 200, function () {
        if (!response)
          throw new Client.Exceptions.ProtocolError(
            "Failed to fetch the API description",
          );

        if (response.version === undefined) {
          throw new Client.Exceptions.ProtocolError(
            "Incompatible protocol version: the client uses v" +
              Client.ProtocolVersion +
              " while the API server uses an unspecified version (pre 1.0)",
          );
        }

        that._private.protocolVersion = response.version;

        if (response.version == Client.ProtocolVersion) {
          return response.response;
        }

        legacyGlobals.v1 = (response.version as string).split(".");
        legacyGlobals.v2 = Client.ProtocolVersion.split(".");

        if (legacyGlobals.v1[0] != legacyGlobals.v2[0]) {
          throw new Client.Exceptions.ProtocolError(
            "Incompatible protocol version: the client uses v" +
              Client.ProtocolVersion +
              " while the API server uses v" +
              response.version,
          );
        }

        console.log(
          "WARNING: The client uses protocol v" +
            Client.ProtocolVersion +
            " while the API server uses v" +
            response.version,
        );

        return response.response;
      });
    },
  });
};

/**
 * Attach API resources from the description to the client.
 * @method HaveAPI.Client#attachResources
 * @private
 */
Client.prototype.attachResources = function () {
  // Detach existing resources
  if (this.resources.length > 0) {
    this.destroyResources();
  }

  this._private.attachedResourceNames = Object.create(null);

  for (var r in this._private.description!.resources) {
    if (!Client.hasOwn(this._private.description!.resources, r)) continue;

    if (this._private.debug > 10) console.log("Attach resource", r);

    var resource = new Client.Resource(
      this,
      null,
      r,
      this._private.description!.resources[r],
      [],
    );

    this.resources.push(resource);

    if (Client.attachDescriptionMember(this, r, resource))
      this._private.attachedResourceNames[r] = true;
  }
};

/**
 * Authenticate using selected authentication method.
 * It is possible to avoid calling {@link HaveAPI.Client#setup} before authenticate completely,
 * when it's certain that the client will be used only after it is authenticated. The client
 * will be then set up more efficiently.
 * @method HaveAPI.Client#authenticate
 * @param {string} method name of authentication provider
 * @param {Object} opts a hash of options that is passed to the authentication provider
 * @param {HaveAPI.Client~doneCallback} callback called when the authentication is finished
 * @param {Boolean} reset if false, the client will not be set up again, defaults to true
 */
Client.prototype.authenticate = function (method, opts, callback, reset) {
  var that = this;

  if (reset === undefined) reset = true;

  if (!this._private.description) {
    // The client has not yet been setup.
    // Fetch the description, do NOT attach the resources, use it only to authenticate.

    this.fetchDescription(function (status, extract) {
      that._private.description = (
        extract as unknown as { call(): unknown }
      ).call() as Description;
      that.createSettings();
      that.authenticate(method, opts, callback);
    });

    return;
  }

  this.authProvider = new legacyGlobals.Authentication.providers[method](
    this,
    opts,
    this._private.description!.authentication[method],
  );

  this.authProvider.setup(function (c, status) {
    // Fetch new description, which may be different when authenticated
    if (status && reset) {
      that.setup(function (c2, status2) {
        callback(c2, status2);
        that._private.hooks!.invoke("after", "authenticated", that, true);
      });
    } else {
      callback(that, status);
      if (status)
        that._private.hooks!.invoke("after", "authenticated", that, true);
    }
  });
};

/**
 * Logout, destroy the authentication provider.
 * {@link HaveAPI.Client#setup} must be called if you want to use
 * the client again.
 * @method HaveAPI.Client#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.logout = function (callback) {
  var that = this;

  this.authProvider.logout(function () {
    that.authProvider = new Client.Authentication.Base();
    that.destroyResources();
    that._private.description = null;

    if (callback !== undefined) callback(that, true);
  });
};

/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#after
 * @param {String} event setup or authenticated
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.after = function (event, callback) {
  this._private.hooks!.register("after", event, callback);
};

/**
 * Set member apiSettings.
 * @method HaveAPI.Client#createSettings
 * @private
 */
Client.prototype.createSettings = function () {
  this.apiSettings = {
    meta: this._private.description!.meta,
  };
};

/**
 * Detach resources from the client.
 * @method HaveAPI.Client#destroyResources
 * @private
 */
Client.prototype.destroyResources = function () {
  while (this.resources.length > 0) {
    var resource = this.resources.shift()!;
    var name = resource.getName();

    if (
      this._private.attachedResourceNames[name] &&
      (this as unknown as Record<string, unknown>)[name] === resource
    ) {
      delete (this as unknown as Record<string, unknown>)[name];
    }
  }

  this._private.attachedResourceNames = Object.create(null);
};

/**
 * Return true if the parameters should be sent as a query parameters,
 * which is the case for GET and OPTIONS methods.
 * @method HaveAPI.Client#sendAsQueryParams
 * @param {String} method HTTP method
 * @return {Boolean}
 * @private
 */
Client.prototype.sendAsQueryParams = function (method) {
  return ["GET", "OPTIONS"].indexOf(method) != -1;
};

/**
 * Add URL encoded parameters to URL.
 * Note that this method does not support object_list or hash_list layouts.
 * @method HaveAPI.Client#addParamsToQuery
 * @param {String} url
 * @param {String} namespace
 * @param {Object} params
 * @private
 */
Client.prototype.addParamsToQuery = function (
  url,
  namespace,
  params,
  paramDesc,
) {
  return addParamsToQuery(url, namespace, params);
};
