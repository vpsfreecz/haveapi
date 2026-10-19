import { Response } from './response';
import type { Action } from './action';
import type { ValidationErrors } from './types';
export interface LocalResponse extends Response {
}
export interface LocalResponseConstructor {
    new (action: Action, status: boolean, message: string, errors: ValidationErrors): LocalResponse;
    prototype: LocalResponse;
}
/**
 * @class LocalResponse
 * @memberof HaveAPI.Client
 * @augments HaveAPI.Client.Response
 */
export declare const LocalResponse: LocalResponseConstructor;
