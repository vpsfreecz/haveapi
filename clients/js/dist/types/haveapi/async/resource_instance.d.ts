import type { AsyncAction, AsyncActionOptions, AsyncResource } from './resource';
import type { IdArgument, Values } from '../types';
import type { AsyncResourceContext, InvocationResult, RequestResult } from './types';
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
