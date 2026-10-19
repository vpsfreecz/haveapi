import { BaseResource } from './base_resource';
import { Client } from './client';
import type { BaseResourcePrivate } from './base_resource';
import type { InvocationArgument } from './action';
import type { ResourceDescription } from './types';
import type { ResourceInstance } from './resource_instance';
export interface ResourcePrivate extends BaseResourcePrivate {
    args: InvocationArgument[];
}
export interface Resource extends BaseResource<ResourcePrivate> {
    (...args: InvocationArgument[]): Resource;
    applyArguments(args: InvocationArgument[]): Resource;
    'new'(): ResourceInstance;
}
export interface ResourceConstructor {
    new (client: Client, parent: BaseResource | null, name: string, description: ResourceDescription, args: InvocationArgument[]): Resource;
    prototype: Resource;
}
/**
 * @class Resource
 * @memberof HaveAPI.Client
 */
export declare const Resource: ResourceConstructor;
