import './authentication';
import type { Provider, AuthenticationOptions, AuthenticationRegistry } from './authentication';
import type { Action, ActionConstructor, ActionCall, ActionReply } from './action';
import type { ActionStateConstructor } from './action_state';
import type { BaseResource, BaseResourceConstructor } from './base_resource';
import type { Resource, ResourceConstructor } from './resource';
import type { ResourceInstanceConstructor } from './resource_instance';
import type { ResourceInstanceListConstructor } from './resource_instance_list';
import type { Response, ResponseConstructor } from './response';
import type { LocalResponseConstructor } from './local_response';
import type { Hooks, HooksConstructor } from './hooks';
import type { Http, HttpConstructor } from './http';
import type { Exceptions } from './exceptions';
import type { ClientOptions, Description, HeaderMap, Language, Params, ParameterDescription, Values, Versions } from './types';
export type DoneCallback = (client: Client, status: boolean) => void;
export type VersionsCallback = (client: Client, status: boolean, versions: Versions | null) => void;
export type CompatibleCallback = (compatible: 'compatible' | 'imperfect' | false) => void;
export type DescriptionCallback = (status: boolean, extract: () => unknown) => void;
export interface ClientInvocationOptions<T = ActionReply> extends ActionCall<T> {
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
    apiSettings: {
        meta: {
            namespace: string;
        };
    } | null;
    resources: Resource[];
    authProvider: Provider;
    sameOriginUrl(url: string, opts?: {
        actionPath?: boolean;
        trustedOrigins?: string[];
    }): string;
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
    authenticate(method: string, opts: AuthenticationOptions, callback: DoneCallback, reset?: boolean): void;
    logout(callback?: DoneCallback): void;
    directInvoke(action: Action, opts: ClientInvocationOptions<Response>): void;
    invoke(action: Action, opts: ClientInvocationOptions): void;
    after(event: string, callback: DoneCallback): void;
    createSettings(): void;
    destroyResources(): void;
    sendAsQueryParams(method: string): boolean;
    addParamsToQuery(url: string, namespace: string | null, params?: Params, paramDesc?: Record<string, ParameterDescription> | null): string;
}
export interface ClientConstructor {
    new (url: string, opts?: ClientOptions): Client;
    prototype: Client;
    Version: string;
    ProtocolVersion: string;
    unsafeAttachmentNames: Record<string, boolean>;
    Exceptions: Exceptions;
    hasOwn(obj: unknown, prop: PropertyKey): boolean;
    canAttachDescriptionMember(target: object, name: unknown, reservedNames?: Record<string, boolean>): boolean;
    attachDescriptionMember(target: object, name: string, value: unknown, reservedNames?: Record<string, boolean>): boolean;
    findResource(root: {
        resources: Resource[];
    }, resourcePath: string[]): Resource;
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
export declare const Client: ClientConstructor;
