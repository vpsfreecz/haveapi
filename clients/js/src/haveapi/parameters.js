/**
 * @class Parameters
 * @private
 * @param {HaveAPI.Client.Action} action
 * @param {Object} input parameters
 */
function Parameters (action, params) {
	this.action = action;
	this.typeErrors = {};
	this.params = this.coerceParams(params);

	/**
	 * @member {Object} Parameters#errors Errors found during the validation.
	 */
	this.errors = {};
}

Parameters.prototype._addTypeError = function (name, msg) {
	if (!this.typeErrors.hasOwnProperty(name))
		this.typeErrors[name] = [];

	this.typeErrors[name].push(msg);
};

function isLeapYear (y) {
	return (y % 4 === 0 && y % 100 !== 0) || (y % 400 === 0);
}

function daysInMonth (y, m) {
	switch (m) {
		case 2:
			return isLeapYear(y) ? 29 : 28;
		case 4:
		case 6:
		case 9:
		case 11:
			return 30;
		default:
			return 31;
	}
}

Parameters.prototype._isIso8601Datetime = function (str) {
	var match = str.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(?:Z|([+\-])(\d{2}):?(\d{2}))?)?$/);

	if (!match)
		return false;

	var year = parseInt(match[1], 10);
	var month = parseInt(match[2], 10);
	var day = parseInt(match[3], 10);

	if (month < 1 || month > 12)
		return false;

	if (day < 1 || day > daysInMonth(year, month))
		return false;

	if (match[4] !== undefined) {
		var hour = parseInt(match[4], 10);
		var minute = parseInt(match[5], 10);
		var second = match[6] !== undefined ? parseInt(match[6], 10) : 0;

		if (hour < 0 || hour > 23)
			return false;

		if (minute < 0 || minute > 59)
			return false;

		if (second < 0 || second > 59)
			return false;
	}

	if (match[8] !== undefined) {
		var offsetHour = parseInt(match[9], 10);
		var offsetMinute = parseInt(match[10], 10);

		if (offsetHour < 0 || offsetHour > 23)
			return false;

		if (offsetMinute < 0 || offsetMinute > 59)
			return false;
	}

	return true;
};

/**
 * Coerce parameters passed to the action to appropriate types.
 * @method Parameters.coerceParams
 * @param {Object} params
 * @return {Object}
 */
Parameters.prototype.coerceParams = function (params) {
	var ret = {};

	if (this.action.description.input === null)
		return ret;

	var input = this.action.description.input.parameters;
	params = params || {};

	for (var p in params) {
		if (!params.hasOwnProperty(p) || !input.hasOwnProperty(p))
			continue;

		var v = params[p];

		if (v === undefined)
			continue;

		if (v === null) {
			if (input[p].type === 'Resource')
				ret[p] = null;
			continue;
		}

		switch (input[p].type) {
			case 'Resource':
				var resourceId = v;

				if (v instanceof ResourceInstance)
					resourceId = v.id;

				if (typeof resourceId === 'number') {
					if (isFinite(resourceId) && Math.floor(resourceId) === resourceId)
						ret[p] = resourceId;
					else
						this._addTypeError(p, 'not a valid resource id');

				} else if (typeof resourceId === 'string') {
					var resourceStr = resourceId.trim();

					if (resourceStr !== '' && resourceStr.match(/^[+-]?\d+$/))
						ret[p] = parseInt(resourceStr, 10);
					else
						this._addTypeError(p, 'not a valid resource id');

				} else {
					this._addTypeError(p, 'not a valid resource id');
				}

				break;

			case 'Integer':
				var intValue;

				if (typeof v === 'number') {
					if (isFinite(v) && Math.floor(v) === v)
						intValue = v;

				} else if (typeof v === 'string') {
					var intStr = v.trim();

					if (intStr !== '' && intStr.match(/^[+-]?\d+$/))
						intValue = parseInt(intStr, 10);
				}

				if (intValue === undefined)
					this._addTypeError(p, 'not a valid integer');
				else
					ret[p] = intValue;

				break;

			case 'Float':
				var floatValue;

				if (typeof v === 'number') {
					if (isFinite(v))
						floatValue = v;

				} else if (typeof v === 'string') {
					var floatStr = v.trim();

					if (floatStr !== '' && floatStr.match(/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/)) {
						floatValue = parseFloat(floatStr);

						if (!isFinite(floatValue))
							floatValue = undefined;
					}
				}

				if (floatValue === undefined)
					this._addTypeError(p, 'not a valid float');
				else
					ret[p] = floatValue;

				break;

			case 'Boolean':
				var boolValue;

				if (typeof v === 'boolean') {
					boolValue = v;

				} else if (typeof v === 'number') {
					if (v === 0)
						boolValue = false;
					else if (v === 1)
						boolValue = true;

				} else if (typeof v === 'string') {
					var boolStr = v.trim();

					if (boolStr !== '') {
						var boolToken = boolStr.toLowerCase();

						if (boolToken === 'true' || boolToken === 't' || boolToken === 'yes' || boolToken === 'y' || boolToken === '1')
							boolValue = true;
						else if (boolToken === 'false' || boolToken === 'f' || boolToken === 'no' || boolToken === 'n' || boolToken === '0')
							boolValue = false;
					}
				}

				if (boolValue === undefined)
					this._addTypeError(p, 'not a valid boolean');
				else
					ret[p] = boolValue;

				break;

			case 'Datetime':
				var dtValue;

				if (v instanceof Date) {
					if (!isNaN(v.getTime()))
						dtValue = v.toISOString();

				} else if (typeof v === 'string') {
					var dtStr = v.trim();

					if (dtStr !== '' && this._isIso8601Datetime(dtStr))
						dtValue = dtStr;
				}

				if (dtValue === undefined)
					this._addTypeError(p, 'not in ISO 8601 format');
				else
					ret[p] = dtValue;

				break;

			case 'String':
			case 'Text':
				if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean')
					ret[p] = String(v);
				else
					this._addTypeError(p, 'not a valid string');

				break;

			default:
				ret[p] = v;
		}
	}

	return ret;
};

/**
 * Validate given input parameters.
 * @method Parameters#validate
 * @return {Boolean}
 */
Parameters.prototype.validate = function () {
	if (this.action.description.input === null)
		return true;

	this.errors = {};
	for (var errName in this.typeErrors) {
		if (!this.typeErrors.hasOwnProperty(errName))
			continue;

		this.errors[errName] = this.typeErrors[errName].slice();
	}

	var input = this.action.description.input.parameters;

	for (var name in input) {
		if (!input.hasOwnProperty(name))
			continue;

		if (this.errors.hasOwnProperty(name))
			continue;

		var p = input[name];

		if (!p.validators)
			continue;

		if (!this.params.hasOwnProperty(name) || this.params[name] === undefined || this.params[name] === null) {
			if (p.validators.present)
				this.errors[name] = ['required parameter missing'];

			continue;
		}

		for (var validatorName in p.validators) {
			var validator = Validator.get(
				validatorName,
				p.validators[validatorName],
				this.params[name],
				this.params
			);

			if (validator === false) {
				console.log("Unsupported validator '"+ validatorName +"' for parameter '"+ name +"'");
				continue;
			}

			if (!validator.isValid()) {
				if (!this.errors.hasOwnProperty(name))
					this.errors[name] = [];

				this.errors[name] = this.errors[name].concat(validator.errors);
			}
		}
	}

	return Object.keys(this.errors).length ? false : true;
};
