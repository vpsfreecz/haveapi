/**
 * @class BaseResource
 * @classdesc Base class for {@link HaveAPI.Client.Resource}
 * and {@link HaveAPI.Client.ResourceInstance}. Implements shared methods.
 * @memberof HaveAPI.Client
 */
function BaseResource (){};

/**
 * Attach child resources as properties.
 * @method HaveAPI.Client.BaseResource#attachResources
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
BaseResource.prototype.attachResources = function(description, args) {
	this.resources = [];

	for(var r in description.resources) {
		this[r] = new Client.Resource(this._private.client, this, r, description.resources[r], args);
		this.resources.push(this[r]);
	}
};

/**
 * Attach child actions as properties.
 * @method HaveAPI.Client.BaseResource#attachActions
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
BaseResource.prototype.attachActions = function(description, args) {
	this.actions = [];

	for(var a in description.actions) {
		var names = [a].concat(description.actions[a].aliases);
		var actionInstance = new Client.Action(this._private.client, this, a, description.actions[a], args);

		for(var i = 0; i < names.length; i++) {
			if (names[i] == 'new')
				continue;

			this[names[i]] = actionInstance;
		}

		this.actions.push(a);
	}
};

/**
 * Return default parameters that are to be sent to the API.
 * Default parameters are overriden by supplied parameters.
 * @method HaveAPI.Client.BaseResource#defaultParams
 * @protected
 * @param {HaveAPI.Client.Action} action
 */
BaseResource.prototype.defaultParams = function(action) {
	return {};
};

/**
 * @method HaveAPI.Client.BaseResource#getName
 * @return {String} resource name
 */
BaseResource.prototype.getName = function () {
	return this._private.name;
};
