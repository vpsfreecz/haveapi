import { Client } from './client';
import { ActionState } from './action_state';
import { Parameters } from './parameters';
import type { BaseResource } from './base_resource';
import type { ResourceInstance } from './resource_instance';
import type { ResourceInstanceList } from './resource_instance_list';
import type { Response } from './response';
import type { ActionDescription, IdArgument, Layout, Meta, Params } from './types';
export type ActionReply = Response | ResourceInstance | ResourceInstanceList;
export type ReplyCallback<T = ActionReply> = (client: Client, reply: T) => void;
export type StateCallback<T = ActionReply> = (client: Client, reply: T, state: ActionState) => void;
export interface ActionCall<T = ActionReply> {
    params?: Params;
    meta?: Meta;
    block?: boolean;
    blockInterval?: number;
    blockUpdateIn?: number;
    onReply?: ReplyCallback<T>;
    onStateChange?: StateCallback<T>;
    onDone?: ReplyCallback<T>;
}
export type InvocationArgument = IdArgument | Params | ActionCall | ReplyCallback<never>;
export interface ActionInvocation<T = ActionReply> {
    (...ids: IdArgument[]): void;
    (...args: [...IdArgument[], ReplyCallback<T>]): void;
    (...args: [...IdArgument[], Params, ReplyCallback<T>]): void;
    (...args: [...IdArgument[], ActionCall<T>]): void;
    (...args: [...IdArgument[], Params]): void;
}
export interface PreparedActionCall extends Omit<ActionCall, 'params'> {
    path: string;
    params: Parameters;
    onReply: ReplyCallback;
}
export interface Action<T extends ActionReply = ActionReply> extends ActionInvocation<T> {
    client: Client;
    resource: BaseResource;
    name: string;
    description: ActionDescription;
    args: InvocationArgument[];
    providedIdArgs: IdArgument[];
    preparedPath: string | null;
    httpMethod(): string;
    namespace(direction: 'input' | 'output'): string | null;
    layout(direction: 'input' | 'output'): Layout | null;
    provideIdArgs(args?: IdArgument[]): void;
    providePath(path: string): void;
    invoke: ActionInvocation<T>;
    directInvoke: ActionInvocation<Response>;
    prepareInvoke(args: ArrayLike<InvocationArgument>): PreparedActionCall;
    prepareParams(args: InvocationArgument[]): ActionCall;
    separateMetaParams(params: Params): Pick<ActionCall, 'params' | 'meta'>;
}
export interface WaitForCompletionOptions<T = ActionReply> extends Omit<ActionCall<T>, 'onDone'> {
    id: number;
    client: Client;
    reply: T;
    /** A failed state poll supplies its raw response instead of the original reply. */
    onDone?: ReplyCallback<T | Response>;
}
export interface ActionConstructor {
    new <T extends ActionReply = ActionReply>(client: Client, resource: BaseResource, name: string, description: ActionDescription, args?: InvocationArgument[]): Action<T>;
    prototype: Action;
    waitForCompletion<T = ActionReply>(opts: WaitForCompletionOptions<T>): void;
}
/**
 * @class Action
 * @memberof HaveAPI.Client
 */
export declare const Action: ActionConstructor;
