import type { HttpOptions } from './types';
export interface Http {
    debug: number;
    request(opts: HttpOptions): void;
}
export interface HttpConstructor {
    new (debug?: number): Http;
    prototype: Http;
}
/**
 * @class Http
 * @memberof HaveAPI.Client
 */
export declare const Http: HttpConstructor;
