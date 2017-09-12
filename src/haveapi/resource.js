/**
 * @class Resource
 * @memberof HaveAPI.Client
 */
function Resource (client, parent, name, description, args) {
	this._private = {
		client: client,
		parent: parent,
		name: name,
		description: description,
		args: args
	};

	this.attachResources(description, args);
	this.attachActions(description, args);

	var that = this;
	var fn = function() {
		return new Resource(
			that._private.client,
			that._private.parent,
			that._private.name,
			that._private.description,
			that._private.args.concat(Array.prototype.slice.call(arguments))
		);
	};
	fn.__proto__ = this;

	return fn;
};

Resource.prototype = new BaseResource();

// Unused
Resource.prototype.applyArguments = function(args) {
	for(var i = 0; i < args.length; i++) {
		this._private.args.push(args[i]);
	}

	return this;
};

/**
 * Return a new, empty resource instance.
 * @method HaveAPI.Client.Resource#new
 * @return {HaveAPI.Client.ResourceInstance} resource instance
 */
Resource.prototype.new = function() {
	return new Client.ResourceInstance(this.client, this.parent, this.create, null, false);
};
