Validator.validators.format = function (opts, value) {
	if (typeof value != 'string')
		return false;

	var rx = new RegExp(opts.rx);

	if (opts.match)
		return value.match(rx) ? true : false;

	return value.match(rx) ? false : true;
};
