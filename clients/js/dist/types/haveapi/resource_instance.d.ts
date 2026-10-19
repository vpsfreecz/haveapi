import { BaseResource } from './base_resource';
import { Client } from './client';
import type { BaseResourcePrivate } from './base_resource';
import type { Action, ReplyCallback } from './action';
import type { Response } from './response';
import type { IdArgument, Meta, ParameterDescription, Values } from './types';
export interface ResourceInstancePrivate extends BaseResourcePrivate {
    action: Action;
    response: Response | Values | null | undefined;
    resolved?: boolean;
    persistent?: boolean;
    attributes: Values;
    associations: Record<string, ResourceInstance>;
    resolveCallbacks?: ReplyCallback<ResourceInstance>[];
}
export interface ResourceInstance extends BaseResource<ResourceInstancePrivate> {
    isOk(): boolean;
    apiResponse(): Response | Values | null | undefined;
    save(callback?: ReplyCallback<ResourceInstance>): void;
    resolveAssociation(attr: string, resourcePath: string[], path?: string): ResourceInstance;
    whenResolved(callback: ReplyCallback<ResourceInstance>): void;
    attachAttributes(attrs: Values): void;
    attachStubAttributes(): void;
    createAttribute(attr: string, desc: ParameterDescription): void;
}
export interface ResourceInstanceConstructor {
    new (client: Client, parent: BaseResource | null, action: Action, response?: Response | Values | null, shell?: boolean, item?: boolean): ResourceInstance;
    prototype: ResourceInstance;
    pathParams(meta?: Meta): IdArgument[];
}
/**
 * @class ResourceInstance
 * @classdesc Represents an instance of a resource from the API. Attributes
 *            are accessible as properties. Associations are directly accessible.
 * @param {HaveAPI.Client}          client
 * @param {HaveAPI.Client.Action}   action    Action that created this instance.
 * @param {HaveAPI.Client.Response} response  If not provided, the instance is either
 *                                            not resoved or not persistent.
 * @param {Boolean}                 shell     If true, the resource is just a shell,
 *                                            it is to be fetched from the API. Used
 *                                            when accessed as an association from another
 *                                            resource instance.
 * @param {Boolean}                 item      When true, this object was returned in a list,
 *                                            therefore response is not a Response instance,
 *                                            but just an object with parameters.
 * @memberof HaveAPI.Client
 */
export declare const ResourceInstance: ResourceInstanceConstructor;
