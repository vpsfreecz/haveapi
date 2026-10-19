import { I18n } from '../i18n';
import { request } from './request';
import { AsyncError, asAsyncError } from './error';
import { authenticate, checkProtocol, descriptionSnapshot, validateParams } from './authentication';
import { waitForCompletion } from './completion';
import { createResource } from './resource';
import type { AsyncResource } from './resource';
import type { InvocationRecord } from './completion';
import type { AuthenticationState } from './authentication';
import type { RequestContext } from './request';
import type { ClientOptions, Description, HeaderMap, Language, Versions } from '../types';
import type { AsyncAuthenticationOptions, AsyncResourceContext, CompletionOptions, CompletionResult, InvocationResult, RequestResult, RequestSpec } from './types';

export class AsyncClient {
	readonly then: undefined = undefined;
	resources: AsyncResource[] = [];
	private readonly baseUrl: string;
	private readonly version: string | number | null;
	private language: Language;
	private languageHeader: string;
	private description: Description | undefined;
	private generation = 0;
	private authentication: AuthenticationState = {headers: {}};
	private roots: Record<string, AsyncResource> = Object.create(null);
	private attached: Record<string, AsyncResource> = Object.create(null);
	private transitions: Promise<void> | undefined;
	private readonly invocations = new WeakMap<object, InvocationRecord>();

	constructor(url: string, options: ClientOptions = {}) {
		while (url.length > 0 && url[url.length - 1] === '/') url = url.slice(0, -1);
		const parsed = new URL(url);
		if (!/^https?:$/.test(parsed.protocol) || parsed.username || parsed.password)
			throw new AsyncError('protocol', 'Invalid API base URL');
		this.baseUrl = url;
		this.version = options.version === undefined ? null : options.version;
		this.language = options.language === undefined ? null : options.language;
		this.languageHeader = options.languageHeader === undefined ? options.language_header || I18n.DEFAULT_LANGUAGE_HEADER : options.languageHeader;
		I18n.requestHeaders(this.language, this.languageHeader);
	}
	setLanguage(language: Language): void {
		I18n.requestHeaders(language, this.languageHeader);
		this.language = language;
	}
	setLanguageHeader(header: string): void {
		I18n.assertHeaderName(header);
		this.languageHeader = header;
	}
	private requestContext(auth: AuthenticationState, metaNamespace: string): RequestContext {
		return {baseUrl: this.baseUrl, metaNamespace, language: this.language, languageHeader: this.languageHeader,
			headers: Object.assign({}, auth.headers), ...(auth.credentials ? {credentials: Object.assign({}, auth.credentials)} : {})};
	}
	/** Explicit per-request headers override configured auth/language headers. */
	request<T = unknown>(spec: RequestSpec): Promise<RequestResult<T>> {
		if (arguments.length !== 1) return Promise.reject(new AsyncError('validation', 'request does not accept callbacks'));
		return request<T>(spec, this.requestContext(this.authentication, this.description ? this.description.meta.namespace : '_meta'));
	}
	private enqueue(operation: () => Promise<void>): Promise<void> {
		const result = (this.transitions || Promise.resolve()).then(operation).catch(error => { throw asAsyncError(error); });
		this.transitions = result.then(() => undefined, () => undefined);
		return result;
	}
	private async fetchDescription(auth: AuthenticationState): Promise<Description> {
		const path = this.version == null ? '/?describe=default' : '/v' + encodeURIComponent(String(this.version)) + '/';
		const result = await request({method: 'OPTIONS', path}, this.requestContext(auth, '_meta'));
		checkProtocol(result);
		return descriptionSnapshot(result.data, this.baseUrl);
	}
	private publish(description: Description, auth: AuthenticationState, expectedGeneration: number): void {
		if (this.generation !== expectedGeneration) throw new AsyncError('protocol', 'Lifecycle result belongs to an older client state', {reason: 'stale-binding'});
		const generation = this.generation + 1;
		const context: AsyncResourceContext = {
			description, metaNamespace: description.meta.namespace, generation,
			request: <T>(spec: RequestSpec) => {
				if (this.generation !== generation) return Promise.reject(new AsyncError('protocol', 'Resource binding belongs to an older client state', {reason: 'stale-binding'}));
				return request<T>(Object.assign({}, spec, {metaNamespace: description.meta.namespace}), this.requestContext(auth, description.meta.namespace));
			},
			validateParams: (action, params) => validateParams(action, params, this.language),
			makeError: (kind, message, details) => new AsyncError(kind, message, details),
			recordInvocation: <T>(value: T, response: RequestResult<unknown>, action: InvocationRecord['action']): InvocationResult<T> => {
				const receipt = {value, response};
				this.invocations.set(receipt, {context, action, stateId: response.meta.action_state_id});
				return receipt;
			}
		};
		const roots: Record<string, AsyncResource> = Object.create(null);
		const resources = Object.keys(description.resources).map(name => {
			const resource = createResource(context, [name]);
			roots[name] = resource;
			return resource;
		});
		// Build everything before replacing any public registry or auth state.
		Object.keys(this.attached).forEach(name => {
			if ((this as unknown as Record<string, unknown>)[name] === this.attached[name]) delete (this as unknown as Record<string, unknown>)[name];
		});
		this.attached = Object.create(null);
		this.description = description;
		this.authentication = auth;
		this.generation = generation;
		this.roots = roots;
		this.resources = resources;
		Object.keys(roots).forEach(name => {
			if (name !== '__proto__' && name !== 'prototype' && name !== 'constructor' && !(name in this)) {
				Object.defineProperty(this, name, {value: roots[name], configurable: true, enumerable: true});
				this.attached[name] = roots[name];
			}
		});
	}
	useDescription(description: Description): void {
		try { this.publish(descriptionSnapshot(description, this.baseUrl), this.authentication, this.generation); }
		catch (error) { throw asAsyncError(error); }
	}
	setup(): Promise<void> {
		if (arguments.length !== 0) return Promise.reject(new AsyncError('validation', 'setup does not accept callbacks'));
		return this.enqueue(async () => {
			const generation = this.generation;
			const description = await this.fetchDescription(this.authentication);
			this.publish(description, this.authentication, generation);
		});
	}
	authenticate(method: string, options: AsyncAuthenticationOptions): Promise<void> {
		if (arguments.length !== 2 || options && Object.prototype.hasOwnProperty.call(options, 'callback'))
			return Promise.reject(new AsyncError('validation', 'authenticate does not accept callbacks'));
		let snapshot: AsyncAuthenticationOptions;
		try {
			snapshot = Object.assign(Object.create(null), options);
			if (options && options.access_token) snapshot.access_token = Object.assign({}, options.access_token);
		} catch (error) { return Promise.reject(asAsyncError(error, 'authentication')); }
		return this.enqueue(async () => {
			const generation = this.generation;
			const description = this.description || await this.fetchDescription(this.authentication);
			const candidate = await authenticate(method, snapshot, description,
				<T>(spec: RequestSpec, state: AuthenticationState) => request<T>(spec, this.requestContext(state, description.meta.namespace)), this.language);
			const authorized = await this.fetchDescription(candidate);
			this.publish(authorized, candidate, generation);
		});
	}
	availableVersions(): Promise<Versions> {
		if (arguments.length !== 0) return Promise.reject(new AsyncError('validation', 'availableVersions does not accept callbacks'));
		return this.request<unknown>({method: 'OPTIONS', path: '/?describe=versions'}).then(result => {
		checkProtocol(result);
		const data = result.data as Partial<Versions> | null;
		if (!data || !Array.isArray(data.versions) || data.versions.some(version => typeof version !== 'string' && typeof version !== 'number') ||
			(typeof data.default !== 'string' && typeof data.default !== 'number'))
			throw new AsyncError('protocol', 'Invalid API version list', {response: result, envelope: result.envelope});
		return data as Versions;
		});
	}
	resource(name: string): AsyncResource {
		if (!Object.prototype.hasOwnProperty.call(this.roots, name)) throw new AsyncError('protocol', 'Resource not found');
		return this.roots[name];
	}
	waitForCompletion<T>(result: InvocationResult<T>, options: CompletionOptions): Promise<CompletionResult<T>> {
		if (arguments.length !== 2 || !options || typeof options !== 'object')
			return Promise.reject(new AsyncError('validation', 'Completion options are required'));
		return waitForCompletion(result, this.invocations.get(result), options);
	}
}
