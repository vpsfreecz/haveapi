import type { Action } from './action';
import type { Envelope, Meta } from './types';
export interface Response<T = unknown> {
    action: Action | undefined;
    envelope: Envelope;
    isOk(): boolean;
    response(): T | null | undefined;
    message(): string | null | undefined;
    meta(): Meta;
}
export interface ResponseConstructor {
    new <T = unknown>(action?: Action, response?: Envelope): Response<T>;
    prototype: Response;
}
/**
 * @class Response
 * @memberof HaveAPI.Client
 */
export declare const Response: ResponseConstructor;
