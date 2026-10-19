import { Client } from './client';
import { ActionState } from './action_state';
import { Parameters } from './parameters';
import { LocalResponse } from './local_response';
import type { ActionStateData } from './action_state';
import type { BaseResource } from './base_resource';
import type { ResourceInstance } from './resource_instance';
import type { ResourceInstanceList } from './resource_instance_list';
import type { Response } from './response';
import type { ActionDescription, IdArgument, Layout, Meta, Params } from './types';

export type ActionReply = Response | ResourceInstance | ResourceInstanceList;
export type ReplyCallback<T = ActionReply> = (client: Client, reply: T) => void;
export type StateCallback<T = ActionReply> = (client: Client, reply: T, state: ActionState) => void;
export interface ActionCall<T = ActionReply> {
	params?: Params;
	meta?: Meta;
	block?: boolean;
	blockInterval?: number;
	blockUpdateIn?: number;
	onReply?: ReplyCallback<T>;
	onStateChange?: StateCallback<T>;
	onDone?: ReplyCallback<T>;
}
// A callback has no inferred endpoint schema until the application supplies one.
export type InvocationArgument = IdArgument | Params | ActionCall | ReplyCallback<never>;
export interface ActionInvocation<T = ActionReply> {
	(...ids: IdArgument[]): void;
	(...args: [...IdArgument[], ReplyCallback<T>]): void;
	(...args: [...IdArgument[], Params, ReplyCallback<T>]): void;
	(...args: [...IdArgument[], ActionCall<T>]): void;
	(...args: [...IdArgument[], Params]): void;
}
export interface PreparedActionCall extends Omit<ActionCall, 'params'> {
	path: string;
	params: Parameters;
	onReply: ReplyCallback;
}
export interface Action<T extends ActionReply = ActionReply> extends ActionInvocation<T> {
	client: Client;
	resource: BaseResource;
	name: string;
	description: ActionDescription;
	args: InvocationArgument[];
	providedIdArgs: IdArgument[];
	preparedPath: string | null;
	httpMethod(): string;
	namespace(direction: 'input' | 'output'): string | null;
	layout(direction: 'input' | 'output'): Layout | null;
	provideIdArgs(args?: IdArgument[]): void;
	providePath(path: string): void;
	invoke: ActionInvocation<T>;
	directInvoke: ActionInvocation<Response>;
	prepareInvoke(args: ArrayLike<InvocationArgument>): PreparedActionCall;
	prepareParams(args: InvocationArgument[]): ActionCall;
	separateMetaParams(params: Params): Pick<ActionCall, 'params' | 'meta'>;
}
export interface WaitForCompletionOptions<T = ActionReply> extends Omit<ActionCall<T>, 'onDone'> {
	id: number;
	client: Client;
	reply: T;
	/** A failed state poll supplies its raw response instead of the original reply. */
	onDone?: ReplyCallback<T | Response>;
}
interface CallbackActionStateResource {
	show(id: number, callback: ReplyCallback<Response>): void;
	poll(id: number, options: ActionCall<Response>): void;
	cancel(id: number, options: ActionCall): void;
}
export interface ActionConstructor {
	new<T extends ActionReply = ActionReply>(client: Client, resource: BaseResource, name: string, description: ActionDescription, args?: InvocationArgument[]): Action<T>;
	prototype: Action;
	waitForCompletion<T = ActionReply>(opts: WaitForCompletionOptions<T>): void;
}

// This reference is unreachable legacy code. Erase its typing without changing
// the original branch or introducing a runtime binding.
declare var opts: ActionCall;

/**
 * @class Action
 * @memberof HaveAPI.Client
 */
export const Action = function Action(this: Action, client: Client, resource: BaseResource, name: string, description: ActionDescription, args?: InvocationArgument[]) {
	if (client._private.debug > 10)
		console.log("Attach action", name, "to", resource._private.name);

	this.client = client;
	this.resource = resource;
	this.name = name;
	this.description = description;
	this.args = args || [];
	this.providedIdArgs = [];
	this.preparedPath = null;

	var that = this;
	var fn = function() {
		var new_a = new (Action as unknown as ActionConstructor)(
			that.client,
			that.resource,
			that.name,
			that.description,
			that.args.concat(Array.prototype.slice.call(arguments))
		);
		return new_a.invoke();
	};
	(fn as unknown as {__proto__: Action}).__proto__ = this;

	return fn;
} as unknown as ActionConstructor;

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
Action.prototype.namespace = function(direction: 'input' | 'output') {
	if (this.description[direction])
		return this.description[direction]!.namespace;

	return null;
};

/**
 * Returns action's layout.
 * @method HaveAPI.Client.Action#layout
 * @param {String} direction input/output
 * @return {String}
 */
Action.prototype.layout = function(direction: 'input' | 'output') {
	if (this.description[direction])
		return this.description[direction]!.layout;

	return null;
};

/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#provideIdArgs
 */
Action.prototype.provideIdArgs = function(args?: IdArgument[]) {
	this.providedIdArgs = args || [];
};

/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#providePath
 */
Action.prototype.providePath = function(path: string) {
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
 *   onReply: function (c: Client, reply: Response) {
 *     console.log('The server has returned a response, the action is being executed.');
 *   },
 *   onStateChange: function  (c, reply, state) {
 *     console.log(
 *       "The action's state has changed, current progress:",
 *       state.progress.toString()
 *     );
 *   },
 *   onDone: function (c: Client, reply: Response) {
 *     console.log('The action is finished');
 *   }
 * });
 *
 * @example
 * // If the API server supports it, blocking actions can be cancelled
 * api.vps.restart(101, {
 *   onReply: function (c: Client, reply: Response) {
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
 *   onDone: function (c: Client, reply: Response) {
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
			this.client.translate('errors.invalid_input_parameters'),
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
			this.client.translate('errors.invalid_input_parameters'),
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
Action.prototype.prepareInvoke = function(new_args: ArrayLike<InvocationArgument>) {
	var args = this.args.concat(Array.prototype.slice.call(new_args));
	var rx = /(\{[a-zA-Z0-9\-_]+\})/;
	var preparedPath = this.preparedPath || this.description.path;
	var providedIdArgs = this.providedIdArgs.slice();

	// First, apply ids returned from the API
	for (var i = 0; i < providedIdArgs.length; i++) {
		if (preparedPath.search(rx) == -1)
			break;

		preparedPath = preparedPath.replace(rx, encodeURIComponent(providedIdArgs[i] as string | number | boolean));
	}

	// Apply ids passed as arguments
	while (args.length > 0) {
		if (preparedPath.search(rx) == -1)
			break;

		var arg = args[0] as InvocationArgument;

		if (typeof(arg) === 'function' || (arg && ((arg as ActionCall).params || (arg as ActionCall).onReply)))
			break;

		args.shift();
		providedIdArgs.push(arg as IdArgument);

		preparedPath = preparedPath.replace(rx, encodeURIComponent(arg as string | number | boolean));
	}

	if (preparedPath.search(rx) != -1) {
		console.log("UnresolvedArguments", this.client.translate(
			'errors.unresolved_arguments',
			{action: this.name}
		));

		throw new Client.Exceptions.UnresolvedArguments(this);
	}

	var that = this;
	var params = this.prepareParams(args);

	// Add default parameters from object instance
	if (this.layout('input') === 'object') {
		var defaults = this.resource.defaultParams(this);

		for (var param in this.description.input!.parameters) {
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
		path: preparedPath,
		params: new Parameters(this, params.params),
		onReply: function(c: Client, response: ActionReply) {
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
Action.prototype.prepareParams = function (args: InvocationArgument[]) {
	if (!args.length)
		return {};

	if (args.length == 1 && ((args[0] as ActionCall).params || (args[0] as ActionCall).onReply)) {
		// Parameters passed in an object
		return args[0] as ActionCall;
	}

	// One parameter is passed, it can be old-style hash of parameters or a callback
	if (args.length == 1) {
		if (typeof(args[0]) === 'function') {
			// The one parameter is a callback -- no input parameters given
			return {onReply: args[0] as ReplyCallback};
		}

		var params = this.separateMetaParams(args[0] as Params);

		return {
			params: params.params,
			meta: params.meta
		};

		var ret: ActionCall = {};

		if (opts.meta) {
			ret.meta = opts.meta;
			delete opts.meta;
		}

		ret.params = opts as unknown as Params;

		return ret;
	}

	// Two or more parameters are passed. The first is a hash of parameters, the second
	// is a callback. The rest is ignored.
	var params = this.separateMetaParams(args[0] as Params);

	return {
		params: params.params,
		meta: params.meta,
		onReply: args[1] as ReplyCallback
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
Action.prototype.separateMetaParams = function (params: Params) {
	var ret: ActionCall = {};

	for (var k in params) {
		if (!params.hasOwnProperty(k))
			continue;

		if (k === 'meta') {
			ret.meta = params[k] as Meta;

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
Action.waitForCompletion = function <T>(opts: WaitForCompletionOptions<T>) {
	var interval = opts.blockInterval || 15;
	var updateIn = opts.blockUpdateIn || 3;

	var updateState = function (state: ActionState) {
		if (!opts.onStateChange)
			return;

		opts.onStateChange(opts.client, opts.reply, state);
	};

	var callOnDone = function (reply?: Response) {
		if (!opts.onDone)
			return;

		opts.onDone(opts.client, reply || opts.reply);
	};

	var onPoll = function (c: Client, reply: Response) {
		if (!reply.isOk())
			return callOnDone(reply);

		var state = new ActionState(reply.response() as ActionStateData);

		updateState(state);

		if (state.finished)
			return callOnDone();

		if (state.shouldStop())
			return;

		if (state.shouldCancel()) {
			if (!state.canCancel)
				throw new Client.Exceptions.UncancelableAction(opts.id, opts.client);

			return (opts.client as unknown as {action_state: CallbackActionStateResource}).action_state.cancel(
				opts.id,
				Object.assign({}, opts, state.cancelOpts) as ActionCall
			);
		}

		(opts.client as unknown as {action_state: CallbackActionStateResource}).action_state.poll(opts.id, {
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

	(opts.client as unknown as {action_state: CallbackActionStateResource}).action_state.show(opts.id, onPoll);
};
