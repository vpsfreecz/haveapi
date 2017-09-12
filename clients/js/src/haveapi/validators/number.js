Validator.validators.number = function (opts, value) {
	var v = (typeof value === 'string') ? parseInt(value) : value;

	if (typeof opts.min === 'number' && v < opts.min)
		return false;

	if (typeof opts.max === 'number' && v > opts.max)
		return false;

	if (typeof opts.step === 'number') {
		if ( (v - (typeof opts.min === 'number' ? opts.min : 0)) % opts.step > 0 )
			return false;
	}

	if (typeof opts.mod === 'number' && !(v % opts.mod === 0))
		return false;

	if (typeof opts.odd === 'number' && v % 2 === 0)
		return false;

	if (typeof opts.even === 'number' && v % 2 > 0)
		return false;

	return true;
};
