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
	new(fn: ValidatorFunction, opts: ValidatorOptions, value: unknown, params: Params): Validator;
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
export const Validator = function Validator(this: Validator, fn: ValidatorFunction, opts: ValidatorOptions, value: unknown, params: Params) {
	this.fn = fn;
	this.opts = opts;
	this.value = value;
	this.params = params;

	/**
	 * @member {Array} Validator#errors Errors found during the validation.
	 */
	this.errors = [];
} as unknown as ValidatorConstructor;

/**
 * @property {Object} Validator.validators Registered validators
 */
Validator.validators = {};

/**
 * Register validator function.
 * @func Validator.register
 * @param {String} name
 * @param {fn} validator function
 */
Validator.register = function (name: string, fn: ValidatorFunction) {
	Validator.validators[name] = fn;
};

/**
 * Get registered validator using its name.
 * @func Validator.get
 * @param {String} name
 * @param {Object} opts validator options from API description
 * @param value the value to validate
 * @param {Object} params object with all parameters
 * @return {Validator}
 */
Validator.get = function (name: string, opts: ValidatorOptions, value: unknown, params: Params) {
	if (!Validator.validators.hasOwnProperty(name))
		return false;

	return new Validator(Validator.validators[name], opts, value, params);
};

/**
 * @method Validator#isValid
 * @return {Boolean}
 */
Validator.prototype.isValid = function () {
	var ret = this.fn(this.opts, this.value, this.params);

	if (ret === true)
		return true;

	if (ret === false) {
		this.errors.push(this.opts.message.replace(/%{value}/g, this.value + ""));
		return false;
	}

	this.errors = this.errors.concat(ret);
	return false;
};
