import type { Params } from './types';

export interface UrlOptions {actionPath?: boolean; pathMode?: 'api' | 'descriptor'; trustedOrigins?: string[]}

export function normalizeTrustedOrigins(origins: string | string[] | null | undefined, makeError: (message: string) => unknown) {
	if (origins === undefined || origins === null)
		return [];

	if (typeof(origins) === 'string')
		origins = [origins];

	if (!Array.isArray(origins))
		throw makeError('Invalid trusted OAuth2 origins');

	return origins.map(function(origin) {
		var parsed;

		if (typeof(origin) !== 'string' || origin.length == 0) {
			throw makeError('Invalid trusted OAuth2 origin');
		}

		if (/[\x00-\x1f\x7f]/.test(origin) || origin.indexOf('\\') != -1) {
			throw makeError('Unsafe trusted OAuth2 origin');
		}

		try {
			parsed = new URL(origin);
		} catch (e) {
			throw makeError('Invalid trusted OAuth2 origin');
		}

		if (!parsed.protocol || !parsed.host || parsed.username || parsed.password ||
		    (parsed.pathname != '' && parsed.pathname != '/') || parsed.search || parsed.hash) {
			throw makeError('Invalid trusted OAuth2 origin');
		}

		return parsed.origin;
	});
}

export function resolveApiUrl(baseUrl: string, url: string, opts: UrlOptions | undefined, makeError: (message: string) => unknown) {
	opts = opts || {};

	if (typeof(url) !== 'string' || url.length == 0) {
		throw makeError('Invalid API URL');
	}

	if (/[\x00-\x1f\x7f]/.test(url) || url.indexOf('\\') != -1) {
		throw makeError('Unsafe API URL');
	}

	var base = new URL(baseUrl);
	var resolved;
	if (base.username || base.password) {
		throw makeError('Unsafe API URL origin');
	}

	if (opts.actionPath) {
		if (url[0] != '/' || url[1] == '/' || url.indexOf('@') != -1) {
			throw makeError('Unsafe API action path');
		}

		resolved = new URL((opts.pathMode === 'api' ? baseUrl : base.origin) + url);

	} else {
		if (url[0] == '/' && url[1] == '/') {
			throw makeError('Unsafe API URL');
		}

		if (url[0] == '/') {
			resolved = new URL(baseUrl + url);

		} else {
			resolved = new URL(url, baseUrl + '/');
		}
	}

	if (resolved.username || resolved.password) {
		throw makeError('Unsafe API URL origin');
	}

	if (resolved.origin != base.origin &&
	    (!opts.trustedOrigins || opts.trustedOrigins.indexOf(resolved.origin) == -1)) {
		throw makeError('Unsafe API URL origin');
	}

	return resolved.href;
}

export function addParamsToQuery(url: string, namespace: string | null, params?: Params, flat?: boolean, owns?: (target: object, key: string) => boolean) {
	if (!params)
		return url;

	var first = true;

	for (var key in params) {
		if (!(owns ? owns(params, key) : params.hasOwnProperty(key)))
			continue;

		var value = params[key];

		if (value === null) {
			value = '';
		} else if (value === undefined) {
			continue;
		}

		if (first) {
			if (url.indexOf('?') == -1)
				url += '?';

			else if (url[ url.length - 1 ] != '&')
				url += '&';

			first = false;

		} else url += '&';

		url += (flat ? encodeURIComponent(key) : encodeURIComponent(namespace as string) + '[' + encodeURIComponent(key) + ']') + '=' + encodeURIComponent(value as string);
	}

	return url;
}
