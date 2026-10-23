import { Client } from './client';
import { Action } from './action';
import type { ClientInvocationOptions } from './client';
import type { Response } from './response';
import type { HttpOptions, Values } from './types';

/**
 * Always calls the callback with {@link HaveAPI.Client.Response} object. It does
 * not interpret the response.
 * @method HaveAPI.Client#directInvoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.directInvoke = function(action, opts) {
	var path = opts.path === undefined ? action.preparedPath : opts.path;

	if (this._private.debug > 5)
		console.log("Executing", action, "with opts", opts, "at", path);

	var that = this;
	var block = opts.block === undefined ? true : opts.block;
	var url = this.sameOriginUrl(path as string, {actionPath: true});

	var httpOpts: HttpOptions = {
		method: action.httpMethod(),
		url: url,
		credentials: this.authProvider.credentials(),
		headers: this.requestHeaders(this.authProvider.headers()),
		queryParameters: this.authProvider.queryParameters(),
		callback: function(status, response) {
			var res = new Client.Response(action, response);

			if(opts.onReply !== undefined)
				opts.onReply(that, res);

			if (action.description.blocking && res.meta().action_state_id && opts.block) {
				if (opts.onStateChange || opts.onDone) {
					Action.waitForCompletion({
						id: res.meta().action_state_id as number,
						client: that,
						reply: res,
						blockInterval: opts.blockInterval,
						blockUpdateIn: opts.blockUpdateIn,
						onStateChange: opts.onStateChange,
						onDone: opts.onDone
					});
				}
			}
		}
	};

	var paramsInQuery = this.sendAsQueryParams(httpOpts.method);
	var metaNs = this.apiSettings!.meta.namespace;

	if (paramsInQuery) {
		httpOpts.url = this.addParamsToQuery(
			httpOpts.url,
			action.namespace('input'),
			opts.params,
			action.description.input ? action.description.input.parameters : null
		);

		if (opts.meta) {
			httpOpts.url = this.addParamsToQuery(
				httpOpts.url,
				metaNs,
				opts.meta
			);
		}

	} else {
		var scopedParams: Values = {};
		var ns = action.namespace('input');

		if (ns)
			scopedParams[ns] = opts.params;

		if (opts.meta)
			scopedParams[metaNs] = opts.meta;

		httpOpts.params = scopedParams;
	}

	try {
		this._private.http!.request(httpOpts);

	} finally {
		action.preparedPath = null;
	}
};

/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#invoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.invoke = function(action, opts) {
	var that = this;
	var origOnReply = opts.onReply;
	var origOnBlock = opts.block === undefined ? true : opts.block;

	(opts as ClientInvocationOptions<Response>).onReply = function (status, response) {
		if (!origOnReply && (!action.description.blocking || (!opts.onStateUpdate && !opts.onDone)))
			return;

		var responseObject;

		switch (action.layout('output')) {
			case 'object':
				responseObject = new Client.ResourceInstance(
					that,
					action.resource._private.parent,
					action,
					response
				);
				break;

			case 'object_list':
				responseObject = new Client.ResourceInstanceList(that, action, response);
				break;

			default:
				responseObject = response;
		}

		if (origOnReply)
			origOnReply(that, responseObject);

		if (action.description.blocking && response.meta().action_state_id && origOnBlock) {
			if (opts.onStateChange || opts.onDone) {
				Action.waitForCompletion({
					id: response.meta().action_state_id as number,
					client: that,
					reply: responseObject,
					blockInterval: opts.blockInterval,
					blockUpdateIn: opts.blockUpdateIn,
					onStateChange: opts.onStateChange,
					onDone: opts.onDone
				});
			}
		}
	};

	opts.block = false;

	this.directInvoke(action, opts);
};
