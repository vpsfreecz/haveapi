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
	this.preparedPath = null;

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
	if (this.description[direction])
		return this.description[direction].namespace;

	return null;
};

/**
 * Returns action's layout.
 * @method HaveAPI.Client.Action#layout
 * @param {String} direction input/output
 * @return {String}
 */
Action.prototype.layout = function(direction) {
	if (this.description[direction])
		return this.description[direction].layout;

	return null;
};

/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#provideIdArgs
 */
Action.prototype.provideIdArgs = function(args) {
	this.providedIdArgs = args;
};

/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#providePath
 */
Action.prototype.providePath = function(path) {
	this.preparedPath = path;
};

/**
 * Invoke the action.
 * This method has a variable number of arguments. Arguments are first applied
 * as object IDs in action path. Then there are two ways in which input parameters
 * can and other options be given to the action.
 *
 * The new-style is to pass {@link HaveAPI.Client~ActionCall} object that contains
 * input parameters, meta parameters and callbacks.
 *
 * The old-style, is to pass an object with parameters (meta parameters are passed
 * within this object) and the second argument is {@link HaveAPI.Client~replyCallback}
 * callback function.  The argument with parameters may be omitted if there aren't any,
 * making the callback function the only additional argument.
 *
 * Arguments do not have to be passed to this method specifically. They may
 * be given to the resources above, the only thing that matters is their correct
 * order.
 *
 * @example
 * // Call with parameters and a callback (new-style).
 * // The first argument '1' is a VPS ID.
 * api.vps.ip_address.list(1, {
 *   params: {limit: 5},
 *   meta: {count: true},
 *   onReply: function(c, reply) {
 * 		console.log("Got", reply.response());
 *   }
 * });
 *
 * @example
 * // Call with parameters and a callback (old-style).
 * // The first argument '1' is a VPS ID.
 * api.vps.ip_address.list(1, {limit: 5, meta: {count: true}}, function(c, reply) {
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
 *
 * @example
 * // Calling blocking actions
 * api.vps.restart(101, {
 *   onReply: function (c, reply) {
 *     console.log('The server has returned a response, the action is being executed.');
 *   },
 *   onStateChange: function  (c, reply, state) {
 *     console.log(
 *       "The action's state has changed, current progress:",
 *       state.progress.toString()
 *     );
 *   },
 *   onDone: function (c, reply) {
 *     console.log('The action is finished');
 *   }
 * });
 *
 * @example
 * // If the API server supports it, blocking actions can be cancelled
 * api.vps.restart(101, {
 *   onReply: function (c, reply) {
 *     console.log('The server has returned a response, the action is being executed.');
 *   },
 *   onStateChange: function  (c, reply, state) {
 *     if (state.canCancel) {
 *       // Cancel action can be blocking too, depends on the API server
 *       state.cancel({
 *         onReply: function () {},
 *         onStateChange: function () {},
 *         onDone: function () {},
 *       });
 *     }
 *   },
 *   onDone: function (c, reply) {
 *     console.log('The action is finished');
 *   }
 * });
 *
 */
Action.prototype.invoke = function() {
	var prep = this.prepareInvoke(arguments);

	if (!prep.params.validate()) {
		prep.onReply(this.client, new LocalResponse(
			this,
			false,
			'invalid input parameters',
			prep.params.errors
		));
		return;
	}

	this.client.invoke(this, Object.assign({}, prep, {
		params: prep.params.params,
	}));
};

/**
 * Same use as {@link HaveAPI.Client.Action#invoke}, except that the callback
 * is always given a {@link HaveAPI.Client.Response} object.
 * @see HaveAPI.Client#directInvoke
 * @method HaveAPI.Client.Action#directInvoke
 */
Action.prototype.directInvoke = function() {
	var prep = this.prepareInvoke(arguments);

	if (!prep.params.validate()) {
		prep.onReply(this.client, new LocalResponse(
			this,
			false,
			'invalid input parameters',
			prep.params.errors
		));
		return;
	}

	this.client.directInvoke(this, Object.assign({}, prep, {
		params: prep.params.params
	}));
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

	if (!this.preparedPath)
		this.preparedPath = this.description.path;

	// First, apply ids returned from the API
	for (var i = 0; i < this.providedIdArgs.length; i++) {
		if (this.preparedPath.search(rx) == -1)
			break;

		this.preparedPath = this.preparedPath.replace(rx, this.providedIdArgs[i]);
	}

	// Apply ids passed as arguments
	while (args.length > 0) {
		if (this.preparedPath.search(rx) == -1)
			break;

		var arg = args.shift();
		this.providedIdArgs.push(arg);

		this.preparedPath = this.preparedPath.replace(rx, arg);
	}

	if (args.length == 0 && this.preparedPath.search(rx) != -1) {
		console.log("UnresolvedArguments", "Unable to execute action '"+ this.name +"': unresolved arguments");

		throw new Client.Exceptions.UnresolvedArguments(this);
	}

	var that = this;
	var params = this.prepareParams(args);

	// Add default parameters from object instance
	if (this.layout('input') === 'object') {
		var defaults = this.resource.defaultParams(this);

		for (var param in this.description.input.parameters) {
			if ( defaults.hasOwnProperty(param) && (
					 !params.params || (params.params && !params.params.hasOwnProperty(param))
				 )) {
				if (!params.params)
					params.params = {};

				params.params[ param ] = defaults[ param ];
			}
		}
	}

	return Object.assign({}, params, {
		params: new Parameters(this, params.params),
		onReply: function(c, response) {
			that.preparedPath = null;

			if (params.onReply)
				params.onReply(c, response);
		},
	});
};

/**
 * Determine what kind of a call type was used and return parameters
 * in a unified object.
 * @private
 * @method HaveAPI.Client.Action#prepareParams
 * @param {Array} mix of input parameters and callbacks
 * @return {Object}
 */
Action.prototype.prepareParams = function (args) {
	if (!args.length)
		return {};

	if (args.length == 1 && (args[0].params || args[0].onReply)) {
		// Parameters passed in an object
		return args[0];
	}

	// One parameter is passed, it can be old-style hash of parameters or a callback
	if (args.length == 1) {
		if (typeof(args[0]) === 'function') {
			// The one parameter is a callback -- no input parameters given
			return {onReply: args[0]};
		}

		var params = this.separateMetaParams(args[0]);

		return {
			params: params.params,
			meta: params.meta
		};

		var ret = {};

		if (opts.meta) {
			ret.meta = opts.meta;
			delete opts.meta;
		}

		ret.params = opts;

		return ret;
	}

	// Two or more parameters are passed. The first is a hash of parameters, the second
	// is a callback. The rest is ignored.
	var params = this.separateMetaParams(args[0]);

	return {
		params: params.params,
		meta: params.meta,
		onReply: args[1]
	};
};

/**
 * Extract meta parameters from `params` and return and object with keys
 * `params` (action's input parameters) and `meta` (action's input meta parameters).
 *
 * @private
 * @method HaveAPI.Client.Action#separateMetaParams
 * @param {Object} action's input parameters, meta parameters may be present
 * @return {Object}
 */
Action.prototype.separateMetaParams = function (params) {
	var ret = {};

	for (var k in params) {
		if (!params.hasOwnProperty(k))
			continue;

		if (k === 'meta') {
			ret.meta = params[k];

		} else {
			if (!ret.params)
				ret.params = {};

			ret.params[k] = params[k];
		}
	}

	return ret;
};

/**
 * @function HaveAPI.Client.Action.waitForCompletion
 * @memberof HaveAPI.Client.Action
 * @static
 * @param {Object} opts
 */
Action.waitForCompletion = function (opts) {
	var interval = opts.blockInterval || 15;
	var updateIn = opts.blockUpdateIn || 3;

	var updateState = function (state) {
		if (!opts.onStateChange)
			return;

		opts.onStateChange(opts.client, opts.reply, state);
	};

	var callOnDone = function (reply) {
		if (!opts.onDone)
			return;

		opts.onDone(opts.client, reply || opts.reply);
	};

	var onPoll = function (c, reply) {
		if (!reply.isOk())
			return callOnDone(reply);

		var state = new ActionState(reply.response());

		updateState(state);

		if (state.finished)
			return callOnDone();

		if (state.shouldStop())
			return;

		if (state.shouldCancel()) {
			if (!state.canCancel)
				throw new Client.Exceptions.UncancelableAction(opts.id);

			return opts.client.action_state.cancel(
				opts.id,
				Object.assign({}, opts, state.cancelOpts)
			);
		}

		opts.client.action_state.poll(opts.id, {
			params: {
				timeout: interval,
				update_in: updateIn,
				current: state.progress.current,
				total: state.progress.total,
				status: state.status
			},
			onReply: onPoll
		});
	};

	opts.client.action_state.show(opts.id, onPoll);
};
