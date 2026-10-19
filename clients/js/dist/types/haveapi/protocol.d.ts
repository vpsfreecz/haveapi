import type { Params } from './types';
export interface UrlOptions {
    actionPath?: boolean;
    trustedOrigins?: string[];
}
export declare function normalizeTrustedOrigins(origins: string | string[] | null | undefined, makeError: (message: string) => unknown): string[];
export declare function resolveApiUrl(baseUrl: string, url: string, opts: UrlOptions | undefined, makeError: (message: string) => unknown): string;
export declare function addParamsToQuery(url: string, namespace: string | null, params?: Params, flat?: boolean, owns?: (target: object, key: string) => boolean): string;
