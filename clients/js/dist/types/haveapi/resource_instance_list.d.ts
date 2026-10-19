import { Client } from './client';
import type { Action } from './action';
import type { ResourceInstance } from './resource_instance';
import type { Response } from './response';
export interface ResourceInstanceList {
    response: Response;
    items: ResourceInstance[];
    length: number;
    totalCount: unknown;
    isOk(): boolean;
    apiResponse(): Response;
    each(fn: (item: ResourceInstance) => void): void;
    itemAt(index: number): ResourceInstance | undefined;
    first(): ResourceInstance | null;
    last(): ResourceInstance | null;
}
export interface ResourceInstanceListConstructor {
    new (client: Client, action: Action, response: Response): ResourceInstanceList;
    prototype: ResourceInstanceList;
}
/**
 * Arguments are the same as for {@link HaveAPI.Client.ResourceInstance}.
 * @class ResourceInstanceList
 * @classdesc Represents a list of {@link HaveAPI.Client.ResourceInstance} objects.
 * @see {@link HaveAPI.Client.ResourceInstance}
 * @memberof HaveAPI.Client
 */
export declare const ResourceInstanceList: ResourceInstanceListConstructor;
