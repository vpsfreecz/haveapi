import { attachMember, createAction, createResource, hasOwn, lookupAction, lookupResource, nonThenable, pathParams, protocolFailure, resolvePath, snapshotAttributes } from './resource';
import type { AsyncAction, AsyncActionOptions, AsyncResource } from './resource';
import type { IdArgument, ParameterDescription, Params, ResourceDescription, Values } from '../types';
import type { AsyncResourceContext, InvocationResult, RequestResult } from './types';

export interface AssociationResult {
	value: AsyncResourceInstance;
	response: RequestResult<unknown> | null;
}

/** Fields are local. Association I/O is available only through loadAssociation. */
export class AsyncResourceInstance {
	readonly then!: undefined;
	private readonly context: AsyncResourceContext;
	private readonly resourcePath: readonly string[];
	private readonly description: ResourceDescription;
	private ids: readonly IdArgument[];
	private attributes: Values;
	private persistent: boolean;
	private readonly associations: Record<string, AsyncResourceInstance> = Object.create(null);
	private readonly attributeNames: Record<string, boolean> = Object.create(null);
	private readonly installedNames: Record<string, boolean> = Object.create(null);
	private saving = false;
	private acceptedUnbound: Error | undefined;

	constructor(context: AsyncResourceContext, path: readonly string[], attributes: Values, ids: readonly IdArgument[] = [], persistent = true) {
		this.context = context;
		this.resourcePath = Object.freeze(path.slice());
		this.description = lookupResource(context, this.resourcePath);
		this.attributes = snapshotAttributes(context, attributes);
		this.ids = Object.freeze(ids.slice());
		this.persistent = persistent;
		nonThenable(this);
		this.installMembers();
	}

	getName(): string { return this.resourcePath[this.resourcePath.length - 1]; }
	get(name: string): unknown { return this.attributes[name]; }
	set(name: string, value: unknown): void {
		Object.defineProperty(this.attributes, name, {value, writable: true, enumerable: true, configurable: true});
		delete this.associations[name];
		this.installAttribute(name);
	}
	isPersistent(): boolean { return this.persistent; }

	action(name: string): AsyncAction { return createAction(this.context, this.resourcePath, name, this.ids); }
	resource(name: string): AsyncResource { return createResource(this.context, this.resourcePath.concat(name), this.ids); }

	private installAttribute(name: string): void {
		if (name === this.context.metaNamespace || hasOwn(this.attributeNames, name))
			return;
		if (name === '__proto__' || name === 'constructor' || name === 'prototype' || name in this)
			return;
		this.attributeNames[name] = true;
		Object.defineProperty(this, name, {enumerable: true, configurable: true,
			get: () => this.attributes[name], set: (value: unknown) => this.set(name, value)});
	}

	private installMembers(): void {
		for (const name of Object.keys(this.installedNames)) {
			delete (this as unknown as Values)[name];
			delete this.installedNames[name];
		}
		for (const name of Object.keys(this.description.resources)) {
			if (!(name in this) && name !== '__proto__' && name !== 'prototype') {
				attachMember(this, name, this.resource(name));
				this.installedNames[name] = true;
			}
		}
		for (const name of Object.keys(this.description.actions)) {
			const action = this.action(name);
			for (const alias of [name].concat(this.description.actions[name].aliases || [])) {
				if (!(alias in this) && alias !== '__proto__' && alias !== 'prototype') {
					attachMember(this, alias, action);
					this.installedNames[alias] = true;
				}
			}
		}
		for (const name of Object.keys(this.attributes))
			this.installAttribute(name);
	}

	private submittedParams(action: import('../types').ActionDescription): Params {
		const params: Params = Object.create(null);
		if (action.input) {
			for (const name of Object.keys(action.input.parameters)) {
				if (hasOwn(this.attributes, name))
					params[name] = this.attributes[name];
			}
		}
		// The action synchronously converts described Resource values and then
		// snapshots the submitted payload before validation or request dispatch.
		return params;
	}

	save(options: Omit<AsyncActionOptions, 'params'> = {}): Promise<InvocationResult<this>> {
		if (this.acceptedUnbound)
			return Promise.reject(this.acceptedUnbound);
		if (this.saving)
			return Promise.reject(this.context.makeError('protocol', 'A save is already in progress'));
		this.saving = true;
		try {
			const name = this.persistent ? 'update' : 'create';
			const action = lookupAction(this.context, this.resourcePath, name);
			const params = this.submittedParams(action);
			return this.action(name)<AsyncResourceInstance>({...options, params}).then(result => {
				const saved = result.value;
				if (!(saved instanceof AsyncResourceInstance))
					throw this.context.makeError('protocol', 'Save requires an object response', {response: result.response});
				// Validate identity and member binding before publishing any state.
				const returned = pathParams(this.context, result.response.meta);
				const ids = returned === undefined && this.persistent ? this.ids : returned || [];
				const update = this.description.actions.update;
				if (update) {
					try { resolvePath(this.context, update.path, ids); }
					catch (error) { throw protocolFailure(this.context, error, result.response); }
				}
				this.attributes = snapshotAttributes(this.context, saved.attributes);
				this.ids = Object.freeze(ids.slice());
				this.persistent = true;
				for (const name of Object.keys(this.associations)) delete this.associations[name];
				this.installMembers();
				return this.context.recordInvocation(this, result.response, action);
			}).then(result => { this.saving = false; return result; }, error => {
				this.saving = false;
				const failure = protocolFailure(this.context, error);
				const response = (failure as Error & {response?: RequestResult<unknown>}).response;
				if (!this.persistent && response && response.envelope.status === true && response.httpStatus >= 200 && response.httpStatus < 300) {
					this.acceptedUnbound = this.context.makeError('protocol', 'Create succeeded, but its response is unusable. Fetch the created resource before further writes.',
						{response, envelope: response.envelope, httpStatus: response.httpStatus, cause: failure, reason: 'accepted-unbound'});
					throw this.acceptedUnbound;
				}
				throw failure;
			});
		} catch (error) {
			this.saving = false;
			return Promise.reject(protocolFailure(this.context, error));
		}
	}

	private associationDescription(name: string): ParameterDescription {
		for (const action of Object.keys(this.description.actions)) {
			const output = this.description.actions[action].output;
			if (output && hasOwn(output.parameters, name) && output.parameters[name].type === 'Resource')
				return output.parameters[name];
		}
		throw this.context.makeError('protocol', 'Unknown association ' + name);
	}

	loadAssociation(name: string, options: AsyncActionOptions = {}): Promise<AssociationResult> {
		try {
			const description = this.associationDescription(name);
			if (!description.resource)
				throw this.context.makeError('protocol', 'Association has no resource path');
			if (hasOwn(this.associations, name))
				return Promise.resolve({value: this.associations[name], response: null});
			const raw = this.attributes[name];
			if (!raw || typeof raw !== 'object' || Array.isArray(raw))
				throw this.context.makeError('protocol', 'Malformed association value');
			const value = raw as Values;
			const meta = value[this.context.metaNamespace] || {};
			if (typeof meta !== 'object' || Array.isArray(meta))
				throw this.context.makeError('protocol', 'Malformed association metadata');
			const ids = pathParams(this.context, meta as Values) || [];
			if ((meta as Values).resolved === true) {
				const associated = new AsyncResourceInstance(this.context, description.resource, value, ids, true);
				this.associations[name] = associated;
				return Promise.resolve({value: associated, response: null});
			}
			return createAction(this.context, description.resource, 'show', ids)<AsyncResourceInstance>(options).then(result => {
				if (!(result.value instanceof AsyncResourceInstance))
					throw this.context.makeError('protocol', 'Association load requires an object response', {response: result.response});
				// A field replaced while the request was in flight owns its newer value.
				if (this.attributes[name] === raw)
					this.associations[name] = result.value;
				return {value: result.value, response: result.response};
			});
		} catch (error) {
			return Promise.reject(protocolFailure(this.context, error));
		}
	}
}
