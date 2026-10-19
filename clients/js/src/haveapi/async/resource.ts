import { AsyncResourceInstance } from './resource_instance';
import { AsyncResourceList } from './resource_list';
import type { ActionDescription, IdArgument, Params, ResourceDescription, Values } from '../types';
import type { AsyncResourceContext, InvocationResult, RequestResult, RequestSpec } from './types';

export interface AsyncActionOptions {
	params?: Params;
	meta?: Values;
	headers?: Record<string, string>;
	signal?: AbortSignal;
	timeoutMs?: number;
}
export interface AsyncAction {
	<T = unknown>(...args: [...IdArgument[], AsyncActionOptions] | IdArgument[]): Promise<InvocationResult<T>>;
	invoke<T = unknown>(...args: [...IdArgument[], AsyncActionOptions] | IdArgument[]): Promise<InvocationResult<T>>;
	readonly then: undefined;
}
export interface AsyncResource {
	(...ids: IdArgument[]): AsyncResource;
	readonly then: undefined;
	getName(): string;
	resource(name: string): AsyncResource;
	action(name: string): AsyncAction;
	'new'(attributes?: Values): AsyncResourceInstance;
}

export function hasOwn(value: object, name: PropertyKey): boolean {
	return Object.prototype.hasOwnProperty.call(value, name);
}

export function nonThenable(value: object): void {
	Object.defineProperty(value, 'then', {value: undefined, enumerable: false, writable: false, configurable: false});
}

/** Description names never replace helpers, prototypes or Promise assimilation. */
export function attachMember(value: object, name: string, member: unknown): void {
	if (name === '__proto__' || name === 'constructor' || name === 'prototype' || name in value)
		return;
	Object.defineProperty(value, name, {value: member, enumerable: true, configurable: true});
}

export function lookupResource(context: AsyncResourceContext, path: readonly string[]): ResourceDescription {
	let resources = context.description.resources;
	let description: ResourceDescription | undefined;
	for (const name of path) {
		if (!hasOwn(resources, name))
			throw context.makeError('protocol', 'Unknown resource ' + path.join('.'));
		description = resources[name];
		resources = description.resources;
	}
	if (!description)
		throw context.makeError('protocol', 'A resource path is required');
	return description;
}

export function lookupAction(context: AsyncResourceContext, path: readonly string[], name: string): ActionDescription {
	const actions = lookupResource(context, path).actions;
	if (hasOwn(actions, name))
		return actions[name];
	for (const key of Object.keys(actions)) {
		if ((actions[key].aliases || []).indexOf(name) !== -1)
			return actions[key];
	}
	throw context.makeError('protocol', 'Unknown action ' + path.concat(name).join('.'));
}

function copyValue(context: AsyncResourceContext, value: unknown, parents: object[], localAttributes = false): unknown {
	if (!value || typeof value !== 'object')
		return value;
	// Local fields may refer to another async entity. Request/meta snapshots must
	// still copy ordinary data, after described Resource inputs become scalar IDs.
	if (localAttributes && value instanceof AsyncResourceInstance)
		return value;
	if (value instanceof Date)
		return new Date(value.getTime());
	if (parents.indexOf(value) !== -1)
		throw context.makeError('protocol', 'Circular action parameters');
	const next = parents.concat(value);
	if (Array.isArray(value))
		return value.map(item => copyValue(context, item, next, localAttributes));
	const result: Values = Object.create(null);
	for (const key of Object.keys(value))
		Object.defineProperty(result, key, {value: copyValue(context, (value as Values)[key], next, localAttributes), writable: true, enumerable: true, configurable: true});
	return result;
}

export function snapshotValues(context: AsyncResourceContext, value: Values): Values {
	if (!value || typeof value !== 'object' || Array.isArray(value))
		throw context.makeError('protocol', 'Action parameters must be an object');
	return copyValue(context, value, []) as Values;
}

/** Local attribute copies preserve entity references without changing wire snapshots. */
export function snapshotAttributes(context: AsyncResourceContext, value: Values): Values {
	if (!value || typeof value !== 'object' || Array.isArray(value))
		throw context.makeError('protocol', 'Resource attributes must be an object');
	return copyValue(context, value, [], true) as Values;
}

/** Omitted identity is distinct from an explicit empty or invalid replacement. */
export function pathParams(context: AsyncResourceContext, meta: Values): readonly IdArgument[] | undefined {
	if (!hasOwn(meta, 'path_params'))
		return undefined;
	if (!Array.isArray(meta.path_params) || meta.path_params.some(id => (typeof id !== 'string' && typeof id !== 'number') || (typeof id === 'number' && !isFinite(id))))
		throw context.makeError('protocol', 'Malformed resource path_params');
	return Object.freeze(meta.path_params.slice()) as readonly IdArgument[];
}

export function resolvePath(context: AsyncResourceContext, pattern: string, ids: readonly IdArgument[]): string {
	let position = 0;
	const resolved = pattern.replace(/\{[a-zA-Z0-9_-]+\}/g, () => {
		if (position >= ids.length)
			throw context.makeError('protocol', 'Unresolved action path arguments');
		const id = ids[position++];
		if ((typeof id !== 'string' && typeof id !== 'number') || (typeof id === 'number' && !isFinite(id)))
			throw context.makeError('protocol', 'Invalid action path argument');
		return encodeURIComponent(id);
	});
	return resolved;
}

function prepareOptions(context: AsyncResourceContext, args: readonly unknown[]): {ids: IdArgument[]; options: AsyncActionOptions} {
	const ids: IdArgument[] = [];
	let options: AsyncActionOptions = {};
	for (let i = 0; i < args.length; i++) {
		const argument = args[i];
		if (argument && typeof argument === 'object' && !Array.isArray(argument)) {
			if (i !== args.length - 1)
				throw context.makeError('protocol', 'Action options must be the last argument');
			const supplied = argument as Values;
			const allowed = ['params', 'meta', 'headers', 'signal', 'timeoutMs'];
			if (Object.keys(supplied).some(key => allowed.indexOf(key) === -1))
				throw context.makeError('protocol', 'Async actions accept params/meta options without callbacks');
			for (const key of ['params', 'meta', 'headers']) {
				if (hasOwn(supplied, key) && (!supplied[key] || typeof supplied[key] !== 'object' || Array.isArray(supplied[key])))
					throw context.makeError('protocol', 'Malformed action ' + key);
			}
			options = {...supplied};
		} else {
			if (typeof argument !== 'string' && typeof argument !== 'number')
				throw context.makeError('protocol', 'Async actions do not accept callbacks or invalid IDs');
			ids.push(argument);
		}
	}
	return {ids, options};
}

function normalizeParams(context: AsyncResourceContext, action: ActionDescription, params?: Params): Params | undefined {
	if (!params)
		return params;
	const normalized: Params = Object.create(null);
	for (const name of Object.keys(params)) {
		let value = params[name];
		const parameter = action.input && action.input.parameters[name];
		if (parameter && parameter.type === 'Resource' && value && typeof value === 'object' && !Array.isArray(value)) {
			const identifier = parameter.value_id || 'id';
			if (value instanceof AsyncResourceInstance)
				value = value.get(identifier);
			else
				value = hasOwn(value, identifier) ? (value as Values)[identifier] : undefined;
			// Undefined would be silently omitted by Parameters; a missing/invalid
			// association identifier must instead reject this submitted Resource.
			if (value == null || (typeof value !== 'string' && typeof value !== 'number')) {
				const errors: Record<string, string[]> = Object.create(null);
				errors[name] = ['Resource value must contain an identifier'];
				throw context.makeError('validation', 'Invalid resource identifier for parameter ' + name,
					{errors});
			}
		}
		normalized[name] = value;
	}
	return snapshotValues(context, normalized);
}

export function protocolFailure(context: AsyncResourceContext, error: unknown, response?: RequestResult<unknown>): Error {
	if (error instanceof Error && typeof (error as Error & {kind?: unknown}).kind === 'string') {
		if (response) {
			const details = error as Error & import('./types').AsyncErrorDetails;
			if (!details.response) details.response = response;
			if (!details.envelope) details.envelope = response.envelope;
			if (details.httpStatus === undefined) details.httpStatus = response.httpStatus;
		}
		return error;
	}
	return context.makeError('protocol', error instanceof Error ? error.message : 'Unable to materialize action response', {cause: error, response});
}

export function materialize(context: AsyncResourceContext, path: readonly string[], action: ActionDescription, response: RequestResult<unknown>): unknown {
	switch (action.output && action.output.layout) {
		case 'object':
			return new AsyncResourceInstance(context, path, response.data as Values, pathParams(context, response.meta) || [], true);
		case 'object_list':
			return new AsyncResourceList(context, path, response);
		default:
			return response.data;
	}
}

export function createAction(context: AsyncResourceContext, path: readonly string[], name: string, ids: readonly IdArgument[] = []): AsyncAction {
	const resourcePath = Object.freeze(path.slice());
	const boundIds = Object.freeze(ids.slice());
	const description = lookupAction(context, resourcePath, name);
	const invoke = function<T = unknown>(...args: unknown[]): Promise<InvocationResult<T>> {
		try {
			const prepared = prepareOptions(context, args);
			const options = prepared.options;
			const placeholders = (description.path.match(/\{[a-zA-Z0-9_-]+\}/g) || []).length;
			// Resource identity can include IDs unused by a collection-level action.
			const inherited = boundIds.slice(0, placeholders);
			if (prepared.ids.length > placeholders - inherited.length)
				throw context.makeError('protocol', 'Unexpected action path arguments');
			const spec: RequestSpec = {
				method: description.method,
				path: resolvePath(context, description.path, inherited.concat(prepared.ids)),
				inputNamespace: description.input && description.input.namespace,
				outputNamespace: description.output && description.output.namespace,
				metaNamespace: context.metaNamespace,
				params: context.validateParams(description, normalizeParams(context, description, options.params)),
				meta: options.meta ? snapshotValues(context, options.meta) : undefined,
				headers: options.headers ? {...options.headers} : undefined,
				signal: options.signal,
				timeoutMs: options.timeoutMs,
			};
			return context.request(spec).then(response => {
				try {
					return context.recordInvocation(materialize(context, resourcePath, description, response) as T, response, description);
				} catch (error) {
					throw protocolFailure(context, error, response);
				}
			});
		} catch (error) {
			return Promise.reject(protocolFailure(context, error));
		}
	};
	const callable = invoke as AsyncAction;
	nonThenable(callable);
	Object.defineProperty(callable, 'invoke', {value: invoke});
	return callable;
}

export function createResource(context: AsyncResourceContext, path: readonly string[], ids: readonly IdArgument[] = []): AsyncResource {
	const resourcePath = Object.freeze(path.slice());
	const boundIds = Object.freeze(ids.slice());
	const description = lookupResource(context, resourcePath);
	const callable = function(...moreIds: IdArgument[]): AsyncResource {
		return createResource(context, resourcePath, boundIds.concat(moreIds));
	} as AsyncResource;
	nonThenable(callable);
	Object.defineProperties(callable, {
		getName: {value: () => resourcePath[resourcePath.length - 1]},
		resource: {value: (name: string) => createResource(context, resourcePath.concat(name), boundIds)},
		action: {value: (name: string) => createAction(context, resourcePath, name, boundIds)},
		new: {value: (attributes: Values = {}) => new AsyncResourceInstance(context, resourcePath, attributes, boundIds, false)},
	});
	for (const child of Object.keys(description.resources))
		attachMember(callable, child, createResource(context, resourcePath.concat(child), boundIds));
	for (const name of Object.keys(description.actions)) {
		const action = createAction(context, resourcePath, name, boundIds);
		for (const alias of [name].concat(description.actions[name].aliases || []))
			attachMember(callable, alias, action);
	}
	return callable;
}
