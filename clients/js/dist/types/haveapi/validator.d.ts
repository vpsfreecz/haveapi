import type { Params } from './types';
export interface ValidatorOptions {
    message: string;
    value?: unknown;
    parameter?: string;
    equal?: boolean;
    values?: unknown[] | Record<string, unknown>;
    rx?: string;
    match?: boolean;
    equals?: number;
    min?: number;
    max?: number;
    step?: number;
    mod?: number;
    odd?: number;
    even?: number;
    empty?: boolean;
}
export type ValidatorFunction = (options: ValidatorOptions, value: unknown, params: Params) => boolean | string[];
export interface Validator {
    fn: ValidatorFunction;
    opts: ValidatorOptions;
    value: unknown;
    params: Params;
    errors: string[];
    isValid(): boolean;
}
export interface ValidatorConstructor {
    new (fn: ValidatorFunction, opts: ValidatorOptions, value: unknown, params: Params): Validator;
    prototype: Validator;
    validators: Record<string, ValidatorFunction>;
    register(name: string, fn: ValidatorFunction): void;
    get(name: string, opts: ValidatorOptions, value: unknown, params: Params): Validator | false;
}
/**
 * @class Validator
 * @private
 * @param {Function} fn validator function
 * @param {Object} opts validator options from API description
 * @param value the value to validate
 * @param {Object} params object with all parameters
 */
export declare const Validator: ValidatorConstructor;
