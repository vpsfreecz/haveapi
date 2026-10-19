import type { HttpOptions, LegacyXMLHttpRequest } from './types';
/** No Promise or new error policy is imposed on the callback transport. */
export declare function openRequest(opts: HttpOptions): LegacyXMLHttpRequest;
export declare function sendRequest(request: LegacyXMLHttpRequest, opts: HttpOptions): void;
