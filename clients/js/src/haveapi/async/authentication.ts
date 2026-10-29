import { Parameters } from "../parameters";
import type { DictionaryPolicy } from "../parameters";
import { I18n } from "../i18n";
import { resolveApiUrl } from "../protocol";
import { AsyncError, asAsyncError } from "./error";
import { isRecord, own } from "./request";
import type {
  ActionDescription,
  AuthenticationDescription,
  Credentials,
  Description,
  HeaderMap,
  Language,
  Params,
  ResourceDescription,
  Values,
} from "../types";
import type {
  AsyncAuthenticationOptions,
  RequestResult,
  RequestSpec,
} from "./types";

export interface AuthenticationState {
  headers: HeaderMap;
  credentials?: Credentials;
}
const dictionaries: DictionaryPolicy = {
  create: <T>() => Object.create(null) as Record<string, T>,
  owns: (target, key) => Object.prototype.hasOwnProperty.call(target, key),
};

export function validateParams(
  action: ActionDescription,
  params: Params | undefined,
  language: Language,
): Params {
  if (params !== undefined && !isRecord(params))
    throw new AsyncError("validation", "Action parameters must be an object");
  const prepared = new Parameters(
    {
      description: action,
      client: {
        translate: (key, values) => I18n.translate(language, key, values),
      },
    },
    undefined,
    dictionaries,
  );
  const input = action.input;
  if (input && params) {
    for (const name of Object.keys(params)) {
      if (!own(input.parameters, name)) continue;
      const entry = dictionaries.create<unknown>();
      entry[name] = params[name];
      // Fresh coercion locals per field; validators still see the complete map.
      Object.assign(prepared.params, prepared.coerceParams(entry));
    }
  }
  if (!prepared.validate())
    throw new AsyncError(
      "validation",
      I18n.translate(language, "errors.invalid_input_parameters"),
      { errors: prepared.errors },
    );
  return prepared.params;
}
function validLayout(layout: unknown): boolean {
  if (layout === null) return true;
  return (
    isRecord(layout) &&
    ["object", "object_list", "hash", "hash_list"].indexOf(
      String(layout.layout),
    ) !== -1 &&
    typeof layout.namespace === "string" &&
    layout.namespace.length > 0 &&
    isRecord(layout.parameters) &&
    Object.keys(layout.parameters).every(
      (name) =>
        isRecord((layout.parameters as Values)[name]) &&
        typeof ((layout.parameters as Values)[name] as Values).type ===
          "string",
    )
  );
}
function validateResources(resources: unknown, baseUrl: string): void {
  if (!isRecord(resources))
    throw new AsyncError("protocol", "Invalid resource description");
  Object.keys(resources).forEach((name) => {
    const resource = resources[name];
    if (
      !isRecord(resource) ||
      !isRecord(resource.actions) ||
      !isRecord(resource.resources)
    )
      throw new AsyncError("protocol", "Invalid resource description");
    Object.keys(resource.actions).forEach((actionName) => {
      const action = (resource.actions as Values)[actionName];
      if (
        !isRecord(action) ||
        typeof action.method !== "string" ||
        !/^[A-Za-z]+$/.test(action.method) ||
        typeof action.path !== "string" ||
        !validLayout(action.input) ||
        !validLayout(action.output) ||
        (action.aliases !== undefined &&
          (!Array.isArray(action.aliases) ||
            action.aliases.some((alias) => typeof alias !== "string"))) ||
        (action.blocking !== undefined && typeof action.blocking !== "boolean")
      )
        throw new AsyncError("protocol", "Invalid action description");
      resolveApiUrl(
        baseUrl,
        action.path,
        { actionPath: true },
        (message) => new AsyncError("protocol", message),
      );
    });
    validateResources(resource.resources, baseUrl);
  });
}
function freeze(value: unknown): void {
  if (value && typeof value === "object") {
    Object.keys(value).forEach((key) => freeze((value as Values)[key]));
    Object.freeze(value);
  }
}
export function descriptionSnapshot(
  value: unknown,
  baseUrl: string,
): Description {
  try {
    if (
      !isRecord(value) ||
      !isRecord(value.authentication) ||
      !isRecord(value.meta) ||
      typeof value.meta.namespace !== "string" ||
      !value.meta.namespace
    )
      throw new AsyncError("protocol", "Invalid API description");
    validateResources(value.resources, baseUrl);
    Object.keys(value.authentication).forEach((method) => {
      const provider = (value.authentication as Values)[method];
      if (!isRecord(provider))
        throw new AsyncError("protocol", "Invalid authentication description");
      if (provider.resources !== undefined)
        validateResources(provider.resources, baseUrl);
    });
    const snapshot = JSON.parse(JSON.stringify(value)) as Description;
    freeze(snapshot);
    return snapshot;
  } catch (error) {
    throw asAsyncError(error);
  }
}
export function checkProtocol(result: RequestResult<unknown>): void {
  if (
    typeof result.envelope.version !== "string" ||
    !/^2\.\d+$/.test(result.envelope.version)
  )
    throw new AsyncError("protocol", "Incompatible API protocol version", {
      httpStatus: result.httpStatus,
      envelope: result.envelope,
      response: result,
    });
}
function authenticationHeader(
  description: AuthenticationDescription,
  token: string,
): HeaderMap {
  if (typeof description.http_header !== "string" || !description.http_header)
    throw new AsyncError("protocol", "Missing authentication HTTP header");
  try {
    I18n.assertHeaderName(description.http_header);
    I18n.assertHeaderValue(token);
  } catch (error) {
    throw asAsyncError(error);
  }
  return { [description.http_header]: token };
}
export async function authenticate(
  method: string,
  options: AsyncAuthenticationOptions,
  description: Description,
  send: <T>(
    spec: RequestSpec,
    state: AuthenticationState,
  ) => Promise<RequestResult<T>>,
  language: Language,
): Promise<AuthenticationState> {
  if (!isRecord(options) || !own(description.authentication, method))
    throw new AsyncError(
      "authentication",
      "Unsupported authentication provider",
    );
  const provider = description.authentication[method];
  if (method === "basic")
    return {
      headers: {},
      credentials: { user: options.user, password: options.password },
    };
  if (method === "oauth2") {
    if (
      !isRecord(options.access_token) ||
      typeof options.access_token.access_token !== "string"
    )
      throw new AsyncError(
        "authentication",
        "An OAuth2 access token is required",
      );
    return {
      headers: authenticationHeader(
        provider,
        options.access_token.access_token,
      ),
    };
  }
  if (method !== "token")
    throw new AsyncError(
      "authentication",
      "Unsupported authentication provider",
    );
  if (own(options, "token")) {
    if (typeof options.token !== "string")
      throw new AsyncError("authentication", "Invalid authentication token");
    return { headers: authenticationHeader(provider, options.token) };
  }
  const resource =
    provider.resources && own(provider.resources, "token")
      ? provider.resources.token
      : undefined;
  if (!resource)
    throw new AsyncError("protocol", "Missing token authentication resource");
  let actionName = "request";
  let input: Params = { lifetime: options.lifetime || "renewable_auto" };
  if (options.interval !== undefined) input.interval = options.interval;
  const initialAction = resource.actions.request;
  if (!initialAction || !initialAction.input)
    throw new AsyncError("protocol", "Missing token request action");
  Object.keys(initialAction.input.parameters).forEach((name) => {
    if (
      name !== "lifetime" &&
      name !== "interval" &&
      options[name] !== undefined
    )
      input[name] = options[name];
  });
  for (;;) {
    if (!own(resource.actions, actionName))
      throw new AsyncError("protocol", "Missing authentication action");
    const action = resource.actions[actionName];
    const result = await send<unknown>(
      {
        method: action.method,
        path: action.path,
        inputNamespace: action.input && action.input.namespace,
        outputNamespace: action.output && action.output.namespace,
        metaNamespace: description.meta.namespace,
        params: validateParams(action, input, language),
      },
      { headers: {} },
    );
    const data = result.data;
    if (
      !isRecord(data) ||
      typeof data.token !== "string" ||
      typeof data.complete !== "boolean"
    )
      throw new AsyncError(
        "protocol",
        "Invalid token authentication response",
        { response: result, envelope: result.envelope },
      );
    if (data.complete)
      return { headers: authenticationHeader(provider, data.token) };
    if (
      typeof data.next_action !== "string" ||
      !own(resource.actions, data.next_action)
    )
      throw new AsyncError(
        "protocol",
        "Missing authentication challenge action",
        { response: result, envelope: result.envelope },
      );
    if (typeof options.onChallenge !== "function")
      throw new AsyncError(
        "authentication",
        "An authentication challenge handler is required",
        { response: result, envelope: result.envelope },
      );
    const challenge = resource.actions[data.next_action];
    const parameters: Values = {};
    Object.keys(challenge.input ? challenge.input.parameters : {}).forEach(
      (name) => {
        if (name !== "token")
          parameters[name] = challenge.input!.parameters[name];
      },
    );
    let answer: Params;
    try {
      answer = await options.onChallenge(data.next_action, parameters);
    } catch (cause) {
      throw new AsyncError(
        "authentication",
        "Authentication challenge failed",
        { cause },
      );
    }
    if (!isRecord(answer))
      throw new AsyncError(
        "authentication",
        "Authentication challenge must return an object",
      );
    input = Object.assign(Object.create(null), answer, { token: data.token });
    actionName = data.next_action;
  }
}
