Validator.validators.confirm = function (opts, value, params) {
	var cond = value === params[ opts.parameter ];

	return opts.equal ? cond : !cond;
};
