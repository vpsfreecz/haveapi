import { Validator } from '../validator';

Validator.validators.accept = function (opts, value) {
	return opts.value === value;
};
