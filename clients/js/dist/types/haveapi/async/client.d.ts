import type { AsyncResource } from './resource';
import type { ClientOptions, Description, Language, Versions } from '../types';
import type { AsyncAuthenticationOptions, CompletionOptions, CompletionResult, InvocationResult, RequestResult, RequestSpec } from './types';
export declare class AsyncClient {
    readonly then: undefined;
    resources: AsyncResource[];
    private readonly baseUrl;
    private readonly version;
    private language;
    private languageHeader;
    private description;
    private generation;
    private authentication;
    private roots;
    private attached;
    private transitions;
    private readonly invocations;
    constructor(url: string, options?: ClientOptions);
    setLanguage(language: Language): void;
    setLanguageHeader(header: string): void;
    private requestContext;
    /** Explicit per-request headers override configured auth/language headers. */
    request<T = unknown>(spec: RequestSpec): Promise<RequestResult<T>>;
    private enqueue;
    private fetchDescription;
    private publish;
    useDescription(description: Description): void;
    setup(): Promise<void>;
    authenticate(method: string, options: AsyncAuthenticationOptions): Promise<void>;
    availableVersions(): Promise<Versions>;
    resource(name: string): AsyncResource;
    waitForCompletion<T>(result: InvocationResult<T>, options: CompletionOptions): Promise<CompletionResult<T>>;
}
