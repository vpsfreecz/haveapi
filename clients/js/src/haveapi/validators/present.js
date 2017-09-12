Validator.validators.present = function (opts, value) {
	if (value === undefined)
		return false;

	if (!opts.empty && typeof value === 'string' && !value.trim().length)
		return false;

	return true;
};
