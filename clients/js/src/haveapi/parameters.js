/**
 * @class Parameters
 * @private
 * @param {HaveAPI.Client.Action} action
 * @param {Object} input parameters
 */
function Parameters (action, params) {
	this.action = action;
	this.params = this.coerceParams(params);

	/**
	 * @member {Object} Parameters#errors Errors found during the validation.
	 */
	this.errors = {};
}

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

	for (var p in params) {
		if (!params.hasOwnProperty(p) || !input.hasOwnProperty(p))
			continue;

		var v = params[p];

		switch (input[p].type) {
			case 'Resource':
				if (params[p] instanceof ResourceInstance)
					ret[p] = v.id;

				else
					ret[p] = v;

				break;

			case 'Integer':
				ret[p] = parseInt(v);
				break;

			case 'Float':
				ret[p] = parseFloat(v);
				break;

			case 'Boolean':
				switch (typeof v) {
					case 'boolean':
						ret[p] = v;
						break;

					case 'string':
						if (v.match(/^(t|true|yes|y)$/i))
							ret[p] = true;

						else if (v.match(/^(f|false|no|n)$/i))
							ret[p] = false;

						else
							ret[p] = undefined;

						break;

					case 'number':
						if (v === 0)
							ret[p] = false;

						else if (v >= 1)
							ret[p] = true;

						else
							ret[p] = undefined;

						break;

					default:
						ret[p] = undefined;
				}

				break;

			case 'Datetime':
				if (v instanceof Date)
					ret[p] = v.toISOString();

				else
					ret[p] = v;

				break;

			case 'String':
			case 'Text':
				ret[p] = v + "";

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

	var input = this.action.description.input.parameters;

	for (var name in input) {
		if (!input.hasOwnProperty(name))
			continue;

		var p = input[name];

		if (!p.validators)
			continue;

		if (!this.params.hasOwnProperty(name) || this.params[name] === undefined) {
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
