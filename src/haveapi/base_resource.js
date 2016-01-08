/**
 * @class BaseResource
 * @classdesc Base class for {@link HaveAPI.Client.Resource}
 * and {@link HaveAPI.Client.ResourceInstance}. Implements shared methods.
 * @memberof HaveAPI.Client
 */
var br = c.BaseResource = function(){};

/**
 * Attach child resources as properties.
 * @method HaveAPI.Client.BaseResource#attachResources
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
br.prototype.attachResources = function(description, args) {
	this.resources = [];
	
	for(var r in description.resources) {
		this.resources.push(r);
		
		this[r] = new Client.Resource(this._private.client, r, description.resources[r], args);
	}
};

/**
 * Attach child actions as properties.
 * @method HaveAPI.Client.BaseResource#attachActions
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
br.prototype.attachActions = function(description, args) {
	this.actions = [];
	
	for(var a in description.actions) {
		var names = [a].concat(description.actions[a].aliases);
		var actionInstance = new Client.Action(this._private.client, this, a, description.actions[a], args);
		
		for(var i = 0; i < names.length; i++) {
			if (names[i] == 'new')
				continue;
			
			this.actions.push(names[i]);
			this[names[i]] = actionInstance;
		}
	}
};

/**
 * Return default parameters that are to be sent to the API.
 * Default parameters are overriden by supplied parameters.
 * @method HaveAPI.Client.BaseResource#defaultParams
 * @protected
 * @param {HaveAPI.Client.Action} action
 */
br.prototype.defaultParams = function(action) {
	return {};
};
