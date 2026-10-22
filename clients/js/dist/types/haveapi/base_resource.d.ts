import { Client } from './client';
import type { Action, InvocationArgument } from './action';
import type { ResourceDescription, Params } from './types';
export interface BaseResourcePrivate {
    client: Client;
    parent: BaseResource | null;
    name: string;
    description: ResourceDescription;
    actionIndex?: Record<string, Action>;
}
export interface BaseResource<P extends BaseResourcePrivate = BaseResourcePrivate> {
    _private: P;
    resources: import('./resource').Resource[];
    actions: string[];
    attachResources(description: ResourceDescription, args: InvocationArgument[]): void;
    attachActions(description: ResourceDescription, args: InvocationArgument[]): void;
    defaultParams(action: Action): Params;
    getName(): string;
}
export interface BaseResourceConstructor {
    new (): BaseResource;
    prototype: BaseResource;
    reservedAttachmentNames: Record<string, boolean>;
}
/**
 * @class BaseResource
 * @classdesc Base class for {@link HaveAPI.Client.Resource}
 * and {@link HaveAPI.Client.ResourceInstance}. Implements shared methods.
 * @memberof HaveAPI.Client
 */
export declare const BaseResource: BaseResourceConstructor;
