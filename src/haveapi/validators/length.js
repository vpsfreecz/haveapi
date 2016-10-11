Validator.validators.length = function (opts, value) {
	if (typeof value != 'string')
		return false;

	var len = value.length;

	if (typeof opts.equals === 'number')
		return len === opts.equals;

	if (typeof opts.min === 'number' && !(typeof opts.max === 'number'))
		return len >= opts.min;

	if (!(typeof opts.min === 'number') && typeof opts.max === 'number')
		return len <= opts.max;

	return len >= opts.min && len <= opts.max;
};
