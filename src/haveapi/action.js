/**
 * @class Action
 * @memberof HaveAPI.Client
 */
function Action (client, resource, name, description, args) {
	if (client._private.debug > 10)
		console.log("Attach action", name, "to", resource._private.name);
	
	this.client = client;
	this.resource = resource;
	this.name = name;
	this.description = description;
	this.args = args;
	this.providedIdArgs = [];
	this.preparedUrl = null;
	
	var that = this;
	var fn = function() {
		var new_a = new Action(
			that.client,
			that.resource,
			that.name,
			that.description,
			that.args.concat(Array.prototype.slice.call(arguments))
		);
		return new_a.invoke();
	};
	fn.__proto__ = this;
	
	return fn;
};

/**
 * Returns action's HTTP method.
 * @method HaveAPI.Client.Action#httpMethod
 * @return {String}
 */
Action.prototype.httpMethod = function() {
	return this.description.method;
};

/**
 * Returns action's namespace.
 * @method HaveAPI.Client.Action#namespace
 * @param {String} direction input/output
 * @return {String}
 */
Action.prototype.namespace = function(direction) {
	return this.description[direction].namespace;
};

/**
 * Returns action's layout.
 * @method HaveAPI.Client.Action#layout
 * @param {String} direction input/output
 * @return {String}
 */
Action.prototype.layout = function(direction) {
	return this.description[direction].layout;
};

/**
 * Set action URL. This method should be used to set fully resolved
 * URL.
 * @method HaveAPI.Client.Action#provideIdArgs
 */
Action.prototype.provideIdArgs = function(args) {
	this.providedIdArgs = args;
};

/**
 * Set action URL. This method should be used to set fully resolved
 * URL.
 * @method HaveAPI.Client.Action#provideUrl
 */
Action.prototype.provideUrl = function(url) {
	this.preparedUrl = url;
};

/**
 * Invoke the action.
 * This method has a variable number of arguments. Arguments are first applied
 * as object IDs in action URL. When there are no more URL parameters to fill,
 * the second last argument is an Object containing parameters to be sent.
 * The last argument is a {@link HaveAPI.Client~replyCallback} callback function.
 * 
 * The argument with parameters may be omitted, if the callback function
 * is in its place.
 * 
 * Arguments do not have to be passed to this method specifically. They may
 * be given to the resources above, the only thing that matters is their correct
 * order.
 * 
 * @example
 * // Call with parameters and a callback.
 * // The first argument '1' is a VPS ID.
 * api.vps.ip_address.list(1, {limit: 5}, function(c, reply) {
 * 		console.log("Got", reply.response());
 * });
 * 
 * @example
 * // Call only with a callback. 
 * api.vps.ip_address.list(1, function(c, reply) {
 * 		console.log("Got", reply.response());
 * });
 * 
 * @example
 * // Give parameters to resources.
 * api.vps(101).ip_address(33).delete();
 * 
 * @method HaveAPI.Client.Action#invoke
 */
Action.prototype.invoke = function() {
	var prep = this.prepareInvoke(arguments);
	
	this.client.invoke(this, prep.params, prep.callback);
};

/**
 * Same use as {@link HaveAPI.Client.Action#invoke}, except that the callback
 * is always given a {@link HaveAPI.Client.Response} object.
 * @see HaveAPI.Client#directInvoke
 * @method HaveAPI.Client.Action#directInvoke
 */
Action.prototype.directInvoke = function() {
	var prep = this.prepareInvoke(arguments);
	
	this.client.directInvoke(this, prep.params, prep.callback);
};

/**
 * Prepare action invocation.
 * @method HaveAPI.Client.Action#prepareInvoke
 * @private
 * @return {Object}
 */
Action.prototype.prepareInvoke = function(new_args) {
	var args = this.args.concat(Array.prototype.slice.call(new_args));
	var rx = /(:[a-zA-Z\-_]+)/;
	
	if (!this.preparedUrl)
		this.preparedUrl = this.description.url;

	for (var i = 0; i < this.providedIdArgs.length; i++) {
		if (this.preparedUrl.search(rx) == -1)
			break;
		
		this.preparedUrl = this.preparedUrl.replace(rx, this.providedIdArgs[i]);
	}
	
	while (args.length > 0) {
		if (this.preparedUrl.search(rx) == -1)
			break;
		
		var arg = args.shift();
		this.providedIdArgs.push(arg);
	
		this.preparedUrl = this.preparedUrl.replace(rx, arg);
	}
	
	if (args.length == 0 && this.preparedUrl.search(rx) != -1) {
		console.log("UnresolvedArguments", "Unable to execute action '"+ this.name +"': unresolved arguments");
		
		throw new Client.Exceptions.UnresolvedArguments(this);
	}
	
	var that = this;
	var hasParams = args.length > 0;
	var isFn = hasParams && args.length == 1 && typeof(args[0]) == "function";
	var params = hasParams && !isFn ? args[0] : null;
	
	if (this.layout('input') == 'object') {
		var defaults = this.resource.defaultParams(this);
		
		for (var param in this.description.input.parameters) {
			if ( defaults.hasOwnProperty(param) && (!params || (params && !params.hasOwnProperty(param))) ) {
				if (!params)
					params = {};
				
				params[ param ] = defaults[ param ];
			}
		}
	}
	
	return {
		params: params,
		callback: function(c, response) {
			that.preparedUrl = null;
			
			if (args.length > 1) {
				args[1](c, response);
				
			} else if(isFn) {
				args[0](c, response);
			}
		}
	}
};
