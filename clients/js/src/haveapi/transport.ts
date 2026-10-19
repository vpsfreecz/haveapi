import { XMLHttpRequest } from './xml_http_request';
import type { HttpOptions, LegacyXMLHttpRequest } from './types';

/** No Promise or new error policy is imposed on the callback transport. */
export function openRequest(opts: HttpOptions): LegacyXMLHttpRequest {
	var request = new XMLHttpRequest();
	if (opts.credentials === undefined)
		request.open(opts.method, opts.url);
	else
		request.open(opts.method, opts.url, true, opts.credentials.user, opts.credentials.password);
	for (var header in opts.headers)
		request.setRequestHeader(header, opts.headers[header]);
	if (opts.params !== undefined)
		request.setRequestHeader('Content-Type', 'application/json; charset=utf-8');
	return request;
}
export function sendRequest(request: LegacyXMLHttpRequest, opts: HttpOptions): void {
	if (opts.params !== undefined)
		request.send(JSON.stringify(opts.params));
	else
		request.send();
}
