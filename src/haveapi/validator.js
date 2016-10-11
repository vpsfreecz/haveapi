/**
 * @class Validator
 * @private
 * @param {Function} fn validator function
 * @param {Object} opts validator options from API description
 * @param value the value to validate
 * @param {Object} params object with all parameters
 */
function Validator (fn, opts, value, params) {
	this.fn = fn;
	this.opts = opts;
	this.value = value;
	this.params = params;

	/**
	 * @member {Array} Validator#errors Errors found during the validation.
	 */
	this.errors = [];
};

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
Validator.register = function (name, fn) {
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
Validator.get = function (name, opts, value, params) {
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
