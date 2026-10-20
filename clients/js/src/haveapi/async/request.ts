import { openRequest, sendRequest } from '../transport';
import { addParamsToQuery, resolveApiUrl } from '../protocol';
import { I18n } from '../i18n';
import { AsyncError, asAsyncError } from './error';
import type { Credentials, Envelope, HeaderMap, HttpOptions, Language, LegacyXMLHttpRequest, Meta, Values } from '../types';
import type { ApiErrors, RequestResult, RequestSpec } from './types';

export interface RequestContext {
	baseUrl: string;
	metaNamespace: string;
	language?: Language;
	languageHeader: string;
	headers: HeaderMap;
	credentials?: Credentials;
}
export function isRecord(value: unknown): value is Values {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
export function own(value: object, key: PropertyKey): boolean {
	return Object.prototype.hasOwnProperty.call(value, key);
}
function isApiErrors(value: unknown): value is ApiErrors {
	return isRecord(value) && Object.keys(value).every(key => {
		const errors = value[key];
		return Array.isArray(errors) ? errors.every(message => typeof message === 'string') : isApiErrors(errors);
	});
}
export function mergeHeaders(...sources: Array<HeaderMap | undefined>): HeaderMap {
	const result: HeaderMap = Object.create(null);
	sources.forEach(source => Object.keys(source || {}).forEach(name => {
		I18n.assertHeaderName(name);
		const value = source![name];
		I18n.assertHeaderValue(value);
		Object.keys(result).forEach(previous => {
			if (previous.toLowerCase() === name.toLowerCase()) delete result[previous];
		});
		result[name] = String(value);
	}));
	return result;
}
function prepare(spec: RequestSpec, context: RequestContext): {http: HttpOptions; metaNamespace: string} {
	if (!spec || typeof spec.method !== 'string' || !/^[A-Za-z]+$/.test(spec.method))
		throw new AsyncError('validation', 'Invalid HTTP method');
	if (spec.timeoutMs !== undefined && (!Number.isFinite(spec.timeoutMs) || spec.timeoutMs <= 0))
		throw new AsyncError('validation', 'Request timeout must be positive');
	if (spec.params !== undefined && !isRecord(spec.params) || spec.meta !== undefined && !isRecord(spec.meta))
		throw new AsyncError('validation', 'Request parameters and metadata must be objects');
	const method = spec.method.toUpperCase();
	const metaNamespace = spec.metaNamespace === undefined ? context.metaNamespace : spec.metaNamespace;
	if (typeof metaNamespace !== 'string' || !metaNamespace ||
		(spec.inputNamespace != null && (typeof spec.inputNamespace !== 'string' || !spec.inputNamespace)) ||
		(spec.outputNamespace != null && (typeof spec.outputNamespace !== 'string' || !spec.outputNamespace)))
		throw new AsyncError('validation', 'Invalid parameter namespace');
	let url = resolveApiUrl(context.baseUrl, spec.path, {actionPath: true}, message => new AsyncError('protocol', message));
	let headers: HeaderMap;
	try { headers = mergeHeaders({Accept: 'application/json'}, context.headers,
		I18n.requestHeaders(context.language, context.languageHeader), spec.headers); }
	catch (cause) { throw new AsyncError('validation', 'Invalid HTTP header', {cause}); }
	const http: HttpOptions = {
		method, url, credentials: context.credentials,
		headers
	};
	if (method === 'GET' || method === 'OPTIONS') {
		url = addParamsToQuery(url, spec.inputNamespace || null, spec.params, spec.inputNamespace == null, own);
		if (spec.meta) url = addParamsToQuery(url, metaNamespace, spec.meta, false, own);
		http.url = url;
	} else {
		const body: Values = spec.inputNamespace == null ? Object.assign(Object.create(null), spec.params) : {[spec.inputNamespace]: spec.params || {}};
		if (spec.meta) body[metaNamespace] = spec.meta;
		http.params = body;
	}
	return {http, metaNamespace};
}
function decode<T>(status: number, text: string, namespace: string | null | undefined, metaNamespace: string): RequestResult<T> {
	let parsed: unknown;
	try { parsed = JSON.parse(text); }
	catch (cause) { throw new AsyncError('protocol', 'Invalid JSON response', {httpStatus: status, cause}); }
	if (!isRecord(parsed) || typeof parsed.status !== 'boolean' ||
		(parsed.message != null && typeof parsed.message !== 'string') ||
		(parsed.errors != null && !isApiErrors(parsed.errors)))
		throw new AsyncError('protocol', 'Invalid API response envelope', {httpStatus: status});
	const envelope = parsed as unknown as Envelope<unknown, ApiErrors>;
	let data: unknown = envelope.response;
	let meta: Meta = {};
	// Keep the validated envelope receipt even if its payload cannot be decoded.
	const result: RequestResult<unknown> = {data, meta, envelope, httpStatus: status};
	if (isRecord(data) && own(data, metaNamespace)) {
		if (!isRecord(data[metaNamespace])) throw new AsyncError('protocol', 'Invalid response metadata', {httpStatus: status, envelope, response: result});
		meta = data[metaNamespace] as Meta;
		result.meta = meta;
	}
	if (status < 200 || status >= 300 || !envelope.status)
		throw new AsyncError('api', envelope.message || 'API request failed', {
			httpStatus: status, envelope, response: result, ...(envelope.errors ? {errors: envelope.errors} : {})
		});
	if (!own(envelope, 'response')) throw new AsyncError('protocol', 'Missing response payload', {httpStatus: status, envelope, response: result});
	if (namespace != null) {
		if (!isRecord(data) || !own(data, namespace))
			throw new AsyncError('protocol', 'Missing response namespace', {httpStatus: status, envelope, response: result});
		data = data[namespace];
	}
	return {data: data as T, meta, envelope, httpStatus: status};
}

/** One transport pipeline for both path requests and described async actions. */
export function request<T>(spec: RequestSpec, context: RequestContext): Promise<RequestResult<T>> {
	return new Promise((resolve, reject) => {
		let xhr: LegacyXMLHttpRequest | undefined;
		let timer: ReturnType<typeof setTimeout> | undefined;
		let settled = false;
		const signal = spec && spec.signal;
		const finish = (error?: unknown, result?: RequestResult<T>) => {
			if (settled) return;
			settled = true;
			if (timer !== undefined) clearTimeout(timer);
			if (signal) signal.removeEventListener('abort', abort);
			if (xhr) xhr.onreadystatechange = xhr.onerror = xhr.onabort = xhr.ontimeout = null;
			if (error !== undefined) reject(asAsyncError(error));
			else resolve(result!);
		};
		const cancel = (kind: 'aborted' | 'timeout') => {
			finish(new AsyncError(kind, kind === 'aborted' ? 'Request aborted' : 'Request timed out'));
			if (xhr && xhr.abort) { try { xhr.abort(); } catch (_) { /* Already settled locally. */ } }
		};
		const abort = () => cancel('aborted');
		try {
			if (signal && signal.aborted) return abort();
			const prepared = prepare(spec, context);
			const outputNamespace = spec.outputNamespace;
			const timeoutMs = spec.timeoutMs;
			xhr = openRequest(prepared.http);
			const active = xhr;
			xhr.onreadystatechange = () => {
				if (active.readyState !== 4 || settled) return;
				if (active.status === 0) return finish(new AsyncError('transport', 'Network request failed', {httpStatus: 0}));
				try { finish(undefined, decode<T>(active.status, active.responseText, outputNamespace, prepared.metaNamespace)); }
				catch (error) { finish(error); }
			};
			xhr.onerror = () => finish(new AsyncError('transport', 'Network request failed'));
			xhr.onabort = () => finish(new AsyncError('aborted', 'Request aborted'));
			xhr.ontimeout = () => finish(new AsyncError('timeout', 'Request timed out'));
			if (signal) {
				signal.addEventListener('abort', abort);
				if (signal.aborted) return abort();
			}
			if (timeoutMs !== undefined) timer = setTimeout(() => cancel('timeout'), timeoutMs);
			sendRequest(xhr, prepared.http);
		} catch (error) { finish(asAsyncError(error, 'transport')); }
	});
}
