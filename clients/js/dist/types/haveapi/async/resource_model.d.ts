import type { ActionDescription, IdArgument, Params, ResourceDescription, Values } from '../types';
import type { AsyncResourceContext, InvocationResult, RequestResult } from './types';
export interface AsyncActionOptions {
    params?: Params;
    meta?: Values;
    headers?: Record<string, string>;
    signal?: AbortSignal;
    timeoutMs?: number;
}
export interface AsyncAction {
    <T = unknown>(...args: [...IdArgument[], AsyncActionOptions] | IdArgument[]): Promise<InvocationResult<T>>;
    invoke<T = unknown>(...args: [...IdArgument[], AsyncActionOptions] | IdArgument[]): Promise<InvocationResult<T>>;
    readonly then: undefined;
}
export interface AsyncResource {
    (...ids: IdArgument[]): AsyncResource;
    readonly then: undefined;
    getName(): string;
    resource(name: string): AsyncResource;
    action(name: string): AsyncAction;
    'new'(attributes?: Values): AsyncResourceInstance;
}
export declare function hasOwn(value: object, name: PropertyKey): boolean;
export declare function nonThenable(value: object): void;
/** Description names never replace helpers, prototypes or Promise assimilation. */
export declare function attachMember(value: object, name: string, member: unknown): void;
export declare function lookupResource(context: AsyncResourceContext, path: readonly string[]): ResourceDescription;
export declare function lookupAction(context: AsyncResourceContext, path: readonly string[], name: string): ActionDescription;
export declare function snapshotValues(context: AsyncResourceContext, value: Values): Values;
/** Local attribute copies preserve entity references without changing wire snapshots. */
export declare function snapshotAttributes(context: AsyncResourceContext, value: Values): Values;
/** Omitted identity is distinct from an explicit empty or invalid replacement. */
export declare function pathParams(context: AsyncResourceContext, meta: Values): readonly IdArgument[] | undefined;
export declare function resolvePath(context: AsyncResourceContext, pattern: string, ids: readonly IdArgument[]): string;
export declare function protocolFailure(context: AsyncResourceContext, error: unknown, response?: RequestResult<unknown>): Error;
export declare function materialize(context: AsyncResourceContext, path: readonly string[], action: ActionDescription, response: RequestResult<unknown>): unknown;
export declare function createAction(context: AsyncResourceContext, path: readonly string[], name: string, ids?: readonly IdArgument[]): AsyncAction;
export declare function createResource(context: AsyncResourceContext, path: readonly string[], ids?: readonly IdArgument[]): AsyncResource;
export interface AssociationResult {
    value: AsyncResourceInstance;
    response: RequestResult<unknown> | null;
}
/** Fields are local. Association I/O is available only through loadAssociation. */
export declare class AsyncResourceInstance {
    readonly then: undefined;
    private readonly context;
    private readonly resourcePath;
    private readonly description;
    private ids;
    private attributes;
    private persistent;
    private readonly associations;
    private readonly attributeNames;
    private readonly installedNames;
    private saving;
    private acceptedUnbound;
    constructor(context: AsyncResourceContext, path: readonly string[], attributes: Values, ids?: readonly IdArgument[], persistent?: boolean);
    getName(): string;
    get(name: string): unknown;
    set(name: string, value: unknown): void;
    isPersistent(): boolean;
    action(name: string): AsyncAction;
    resource(name: string): AsyncResource;
    private installAttribute;
    private installMembers;
    private submittedParams;
    save(options?: Omit<AsyncActionOptions, 'params'>): Promise<InvocationResult<this>>;
    private associationDescription;
    loadAssociation(name: string, options?: AsyncActionOptions): Promise<AssociationResult>;
}
/** Local list operations never issue a request or return callback-owned objects. */
export declare class AsyncResourceList implements Iterable<AsyncResourceInstance> {
    readonly [index: number]: AsyncResourceInstance;
    readonly then: undefined;
    readonly items: readonly AsyncResourceInstance[];
    readonly length: number;
    readonly totalCount: unknown;
    [Symbol.iterator]: () => IterableIterator<AsyncResourceInstance>;
    constructor(context: AsyncResourceContext, path: readonly string[], response: RequestResult<unknown>);
    itemAt(index: number): AsyncResourceInstance | undefined;
    first(): AsyncResourceInstance | null;
    last(): AsyncResourceInstance | null;
    each(fn: (item: AsyncResourceInstance, index: number) => void): void;
}
