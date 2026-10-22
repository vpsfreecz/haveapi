import { Client } from './client';
import type { Action, InvocationArgument } from './action';
import type { ResourceDescription, Params } from './types';

export interface BaseResourcePrivate {
	client: Client;
	parent: BaseResource | null;
	name: string;
	description: ResourceDescription;
	actionIndex?: Record<string, Action>;
}

export interface BaseResource<P extends BaseResourcePrivate = BaseResourcePrivate> {
	_private: P;
	resources: import('./resource').Resource[];
	actions: string[];
	attachResources(description: ResourceDescription, args: InvocationArgument[]): void;
	attachActions(description: ResourceDescription, args: InvocationArgument[]): void;
	defaultParams(action: Action): Params;
	getName(): string;
}

export interface BaseResourceConstructor {
	new(): BaseResource;
	prototype: BaseResource;
	reservedAttachmentNames: Record<string, boolean>;
}

// Constructor/prototype bridges preserve the original callable inheritance model.

/**
 * @class BaseResource
 * @classdesc Base class for {@link HaveAPI.Client.Resource}
 * and {@link HaveAPI.Client.ResourceInstance}. Implements shared methods.
 * @memberof HaveAPI.Client
 */
export const BaseResource = function BaseResource(this: BaseResource) {} as unknown as BaseResourceConstructor;

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
BaseResource.prototype.attachResources = function(description: ResourceDescription, args: InvocationArgument[]) {
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
BaseResource.prototype.attachActions = function(description: ResourceDescription, args: InvocationArgument[]) {
	this.actions = [];
	var index: Record<string, Action> = Object.create(null);
	var aliases: Record<string, Action | null> = Object.create(null);
	this._private.actionIndex = index;

	for(var a in description.actions) {
		if (!Client.hasOwn(description.actions, a))
			continue;

		var names = [a].concat(description.actions[a].aliases || []);
		var actionInstance = new Client.Action(this._private.client, this, a, description.actions[a], args);
		index[a] = actionInstance;

		for(var i = 0; i < names.length; i++) {
			Client.attachDescriptionMember(
				this,
				names[i],
				actionInstance,
				BaseResource.reservedAttachmentNames
			);
			if (i > 0 && typeof names[i] === 'string') {
				var alias = names[i];
				if (!Client.hasOwn(aliases, alias))
					aliases[alias] = actionInstance;
				else if (aliases[alias] !== actionInstance)
					aliases[alias] = null;
			}
		}

		this.actions.push(a);
	}
	for (var alias in aliases) {
		if (!Client.hasOwn(index, alias) && aliases[alias] !== null)
			index[alias] = aliases[alias]!;
	}
};

/**
 * Return default parameters that are to be sent to the API.
 * Default parameters are overriden by supplied parameters.
 * @method HaveAPI.Client.BaseResource#defaultParams
 * @protected
 * @param {HaveAPI.Client.Action} action
 */
BaseResource.prototype.defaultParams = function(action: Action) {
	return {};
};

/**
 * @method HaveAPI.Client.BaseResource#getName
 * @return {String} resource name
 */
BaseResource.prototype.getName = function () {
	return this._private.name;
};
