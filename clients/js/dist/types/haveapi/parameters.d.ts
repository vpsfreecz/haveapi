import type { Params, ParameterContext, ValidationErrors, Values } from './types';
export interface DictionaryPolicy {
    create<T>(): Record<string, T>;
    owns(target: object, key: string): boolean;
}
export interface Parameters {
    /** Present only for callers that opt into safe dictionary ownership. */
    _dictionaryPolicy?: DictionaryPolicy;
    action: ParameterContext;
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
    new (action: ParameterContext, params?: Params, dictionaryPolicy?: DictionaryPolicy): Parameters;
    prototype: Parameters;
}
/**
 * @class Parameters
 * @private
 * @param {HaveAPI.Client.Action} action
 * @param {Object} input parameters
 */
export declare const Parameters: ParametersConstructor;
