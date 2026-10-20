/** Values cross this boundary only after the caller or protocol has supplied them. */
export type Values = Record<string, unknown>;
export type Params = Values;
export type Meta = Values;
export type HeaderMap = Record<string, string>;
export type ValidationErrors = Record<string, string[]>;
export type Layout = 'object' | 'object_list' | 'hash' | 'hash_list';
export type Language = string | number | boolean | null;
export type IdArgument = string | number | boolean | null | undefined;
export interface ClientOptions {
    version?: string | number | null;
    debug?: number;
    oauth2TrustedOrigins?: string | string[] | null;
    oauth2_trusted_origins?: string | string[] | null;
    language?: Language;
    languageHeader?: string;
    language_header?: string;
}
export interface ParameterDescription {
    type: string;
    required?: boolean | null;
    nullable?: boolean;
    label?: string;
    description?: string;
    default?: unknown;
    protected?: boolean;
    validators?: Record<string, Values>;
    resource?: string[];
    value_id?: string;
    value_label?: string;
    value?: {
        path: string;
        method: string;
        help?: string;
    };
    choices?: Values;
}
export interface ParameterLayout {
    layout: Layout;
    namespace: string;
    parameters: Record<string, ParameterDescription>;
}
export interface ActionDescription {
    auth?: boolean;
    description?: string;
    aliases?: string[];
    blocking?: boolean;
    method: string;
    path: string;
    help?: string;
    input: ParameterLayout | null;
    output: ParameterLayout | null;
    meta?: unknown;
}
export interface ResourceDescription {
    description?: string;
    actions: Record<string, ActionDescription>;
    resources: Record<string, ResourceDescription>;
}
export interface AuthenticationDescription {
    http_header?: string;
    query_parameter?: string;
    revoke_url?: string;
    resources?: Record<string, ResourceDescription>;
}
export interface Description {
    authentication: Record<string, AuthenticationDescription>;
    resources: Record<string, ResourceDescription>;
    meta: {
        namespace: string;
    };
    help?: string;
}
export interface Versions {
    versions: Array<string | number>;
    default: string | number;
}
export interface Envelope<T = unknown, Errors = ValidationErrors> {
    status: boolean;
    response?: T | null;
    message?: string | null;
    errors?: Errors | null;
    version?: string;
}
export interface Credentials {
    user?: string;
    password?: string;
}
/** Legacy transport status is false when JSON cannot be decoded. */
export type HttpStatus = number | false;
export type HttpCallback = (status: HttpStatus, response?: Envelope) => void;
export interface HttpOptions {
    method: string;
    url: string;
    credentials?: Credentials;
    headers?: HeaderMap;
    queryParameters?: Values;
    params?: unknown;
    callback?: HttpCallback;
}
/** The XHR package and the browser share this small legacy transport interface. */
export interface LegacyXMLHttpRequest {
    readyState: number;
    status: number;
    responseText: string;
    debug?: number;
    open(method: string, url: string, async?: boolean, user?: string, password?: string): void;
    setRequestHeader(name: string, value: string): void;
    onreadystatechange: ((this: LegacyXMLHttpRequest) => void) | null;
    onerror?: (() => void) | null;
    onabort?: (() => void) | null;
    ontimeout?: (() => void) | null;
    abort?(): void;
    send(body?: string): void;
}
export interface LegacyXMLHttpRequestConstructor {
    new (): LegacyXMLHttpRequest;
}
/** Shared validation needs descriptions and translation, not a callback client. */
export interface ParameterContext {
    description: ActionDescription;
    client: {
        translate(key: string, values?: Values): string;
    };
}
