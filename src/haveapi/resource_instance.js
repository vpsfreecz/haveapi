/**
 * @class ResourceInstance
 * @classdesc Represents an instance of a resource from the API. Attributes
 *            are accessible as properties. Associations are directly accessible.
 * @param {HaveAPI.Client}          client
 * @param {HaveAPI.Client.Action}   action    Action that created this instance.
 * @param {HaveAPI.Client.Response} response  If not provided, the instance is either
 *                                            not resoved or not persistent.
 * @param {Boolean}                 shell     If true, the resource is just a shell,
 *                                            it is to be fetched from the API. Used
 *                                            when accessed as an association from another
 *                                            resource instance.
 * @param {Boolean}                 item      When true, this object was returned in a list,
 *                                            therefore response is not a Response instance,
 *                                            but just an object with parameters.
 * @memberof HaveAPI.Client
 */
function ResourceInstance (client, parent, action, response, shell, item) {
	this._private = {
		client: client,
		parent: parent,
		action: action,
		response: response,
		name: action.resource._private.name,
		description: action.resource._private.description
	};

	if (!response) {
		if (shell !== undefined && shell) { // association that is to be fetched
			this._private.resolved = false;
			this._private.persistent = true;

			var that = this;

			action.directInvoke(function(c, response) {
				that.attachResources(that._private.action.resource._private.description, response.meta().url_params);
				that.attachActions(that._private.action.resource._private.description, response.meta().url_params);
				that.attachAttributes(response.response());

				that._private.resolved = true;

				if (that._private.resolveCallbacks !== undefined) {
					for (var i = 0; i < that._private.resolveCallbacks.length; i++)
						that._private.resolveCallbacks[i](that._private.client, that);

					delete that._private.resolveCallbacks;
				}
			});

		} else { // a new, empty instance
			this._private.resolved = true;
			this._private.persistent = false;

			this.attachResources(this._private.action.resource._private.description, action.providedIdArgs);
			this.attachActions(this._private.action.resource._private.description, action.providedIdArgs);
			this.attachStubAttributes();
		}

	} else if (item || response.isOk()) {
		this._private.resolved = true;
		this._private.persistent = true;

		var metaNs = client.apiSettings.meta.namespace;
		var idArgs = item ? response[metaNs].url_params : response.meta().url_params;

		this.attachResources(this._private.action.resource._private.description, idArgs);
		this.attachActions(this._private.action.resource._private.description, idArgs);
		this.attachAttributes(item ? response : response.response());

	} else {
		// FIXME
	}
};

ResourceInstance.prototype = new BaseResource();

/**
 * @callback HaveAPI.Client.ResourceInstance~resolveCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.ResourceInstance} resource
 */

/**
 * A shortcut to {@link HaveAPI.Client.Response#isOk}.
 * @method HaveAPI.Client.ResourceInstance#isOk
 * @return {Boolean}
 */
ResourceInstance.prototype.isOk = function() {
	return this._private.response.isOk();
};

/**
 * Return the response that this instance is created from.
 * @method HaveAPI.Client.ResourceInstance#apiResponse
 * @return {HaveAPI.Client.Response}
 */
ResourceInstance.prototype.apiResponse = function() {
	return this._private.response;
};

/**
 * Save the instance. It calls either an update or a create action,
 * depending on whether the object is persistent or not.
 * @method HaveAPI.Client.ResourceInstance#save
 * @param {HaveAPI.Client~replyCallback} callback
 */
ResourceInstance.prototype.save = function(callback) {
	var that = this;

	function updateAttrs(attrs) {
		for (var attr in attrs) {
			that._private.attributes[ attr ] = attrs[ attr ];
		}
	};

	function replyCallback(c, reply) {
		that._private.response = reply;
		updateAttrs(reply);

		if (callback !== undefined)
			callback(c, that);
	}

	if (this._private.persistent) {
		this.update.directInvoke(replyCallback);

	} else {
		this.create.directInvoke(function(c, reply) {
			if (reply.isOk())
				that._private.persistent = true;

			replyCallback(c, reply);
		});
	}
};

ResourceInstance.prototype.defaultParams = function(action) {
	ret = {}

	for (var attr in this._private.attributes) {
		var desc = action.description.input.parameters[ attr ];

		if (desc === undefined)
			continue;

		switch (desc.type) {
			case 'Resource':
				ret[ attr ] = this._private.attributes[ attr ][ desc.value_id ];
				break;

			default:
				ret[ attr ] = this._private.attributes[ attr ];
		}
	}

	return ret;
};

/**
 * Resolve an associated resource.
 * A shell {@link HaveAPI.Client.ResourceInstance} instance is created
 * and is fetched asynchronously.
 * @method HaveAPI.Client.ResourceInstance#resolveAssociation
 * @private
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstance.prototype.resolveAssociation = function(attr, path, url) {
	var tmp = this._private.client;

	for(var i = 0; i < path.length; i++) {
		tmp = tmp[ path[i] ];
	}

	var obj = this._private.attributes[ attr ];
	var metaNs = this._private.client.apiSettings.meta.namespace;
	var action = tmp.show;
	action.provideIdArgs(obj[metaNs].url_params);

	if (obj[metaNs].resolved)
		return new Client.ResourceInstance(
			this._private.client,
			action.resource._private.parent,
			action,
			obj,
			false,
			true
		);

	return new Client.ResourceInstance(
		this._private.client,
		action.resource._private.parent,
		action,
		null,
		true
	);
};

/**
 * Register a callback that will be called then this instance will
 * be fully resolved (fetched from the API).
 * @method HaveAPI.Client.ResourceInstance#whenResolved
 * @param {HaveAPI.Client.ResourceInstance~resolveCallback} callback
 */
ResourceInstance.prototype.whenResolved = function(callback) {
	if (this._private.resolved)
		callback(this._private.client, this);

	else {
		if (this._private.resolveCallbacks === undefined)
			this._private.resolveCallbacks = [];

		this._private.resolveCallbacks.push(callback);
	}
};

/**
 * Attach all attributes as properties.
 * @method HaveAPI.Client.ResourceInstance#attachAttributes
 * @private
 * @param {Object} attrs
 */
ResourceInstance.prototype.attachAttributes = function(attrs) {
	this._private.attributes = attrs;
	this._private.associations = {};

	var metaNs = this._private.client.apiSettings.meta.namespace;

	for (var attr in attrs) {
		if (attr === metaNs)
			continue;

		this.createAttribute(attr, this._private.action.description.output.parameters[ attr ]);
	}
};

/**
 * Attach all attributes as null properties. Used when creating a new, empty instance.
 * @method HaveAPI.Client.ResourceInstance#attachStubAttributes
 * @private
 */
ResourceInstance.prototype.attachStubAttributes = function() {
	var attrs = {};
	var params = this._private.action.description.input.parameters;

	for (var attr in params) {
		switch (params[ attr ].type) {
			case 'Resource':
				attrs[ attr ] = {};
				attrs[ attr ][ params[attr].value_id ] = null;
				attrs[ attr ][ params[attr].value_label ] = null;
				break;

			default:
				attrs[ attr ] = null;
		}
	}

	this.attachAttributes(attrs);
};

/**
 * Define getters and setters for an attribute.
 * @method HaveAPI.Client.ResourceInstance#createhAttribute
 * @private
 * @param {String} attr
 * @param {Object} desc
 */
ResourceInstance.prototype.createAttribute = function(attr, desc) {
	var that = this;

	switch (desc.type) {
		case 'Resource':
			Object.defineProperty(this, attr, {
				get: function() {
						if (that._private.associations.hasOwnProperty(attr))
							return that._private.associations[ attr ];

						return that._private.associations[ attr ] = that.resolveAssociation(
							attr,
							desc.resource,
							that._private.attributes[ attr ].url
						);
					},
				set: function(v) {
						that._private.attributes[ attr ][ desc.value_id ]    = v.id;
						that._private.attributes[ attr ][ desc.value_label ] = v[ desc.value_label ];
					}
			});

			Object.defineProperty(this, attr + '_id', {
				get: function()  { return that._private.attributes[ attr ][ desc.value_id ];  },
				set: function(v) { that._private.attributes[ attr ][ desc.value_id ] = v;     }
			});

			break;

		default:
			Object.defineProperty(this, attr, {
				get: function()  { return that._private.attributes[ attr ];  },
				set: function(v) { that._private.attributes[ attr ] = v;     }
			});
	}
};
