/**
 * @class BaseResource
 * @classdesc Base class for {@link HaveAPI.Client.Resource}
 * and {@link HaveAPI.Client.ResourceInstance}. Implements shared methods.
 * @memberof HaveAPI.Client
 */
function BaseResource (){};

BaseResource.reservedAttachmentNames = Object.create(null);
BaseResource.reservedAttachmentNames['_private'] = true;
BaseResource.reservedAttachmentNames['resources'] = true;
BaseResource.reservedAttachmentNames['actions'] = true;
BaseResource.reservedAttachmentNames['new'] = true;

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
		if (!Client.hasOwn(description.resources, r))
			continue;

		var resource = new Client.Resource(this._private.client, this, r, description.resources[r], args);

		this.resources.push(resource);

		Client.attachDescriptionMember(this, r, resource, BaseResource.reservedAttachmentNames);
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
		if (!Client.hasOwn(description.actions, a))
			continue;

		var names = [a].concat(description.actions[a].aliases || []);
		var actionInstance = new Client.Action(this._private.client, this, a, description.actions[a], args);

		for(var i = 0; i < names.length; i++) {
			Client.attachDescriptionMember(
				this,
				names[i],
				actionInstance,
				BaseResource.reservedAttachmentNames
			);
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
