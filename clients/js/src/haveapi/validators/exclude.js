Validator.validators.exclude = function (opts, value) {
	if (opts.values instanceof Array)
		return opts.values.indexOf(value) === -1;

	return !opts.values.hasOwnProperty(value);
};
