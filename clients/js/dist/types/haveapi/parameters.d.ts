import type { Action } from './action';
import type { Params, ValidationErrors, Values } from './types';
export interface Parameters {
    action: Action;
    typeErrors: ValidationErrors;
    params: Params;
    errors: ValidationErrors;
    _addTypeError(name: string, message: string): void;
    _message(key: string, values?: Values): string;
    _isIso8601Datetime(value: string): boolean;
    coerceParams(params?: Params): Params;
    validate(): boolean;
}
export interface ParametersConstructor {
    new (action: Action, params?: Params): Parameters;
    prototype: Parameters;
}
/**
 * @class Parameters
 * @private
 * @param {HaveAPI.Client.Action} action
 * @param {Object} input parameters
 */
export declare const Parameters: ParametersConstructor;
