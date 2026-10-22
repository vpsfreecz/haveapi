import type { Credentials, HeaderMap, Language, Values } from '../types';
import type { RequestResult, RequestSpec } from './types';
export interface RequestContext {
    baseUrl: string;
    pathMode?: 'api' | 'descriptor';
    metaNamespace: string;
    language?: Language;
    languageHeader: string;
    headers: HeaderMap;
    credentials?: Credentials;
}
export declare function isRecord(value: unknown): value is Values;
export declare function own(value: object, key: PropertyKey): boolean;
export declare function mergeHeaders(...sources: Array<HeaderMap | undefined>): HeaderMap;
/** One transport pipeline for both path requests and described async actions. */
export declare function request<T>(spec: RequestSpec, context: RequestContext): Promise<RequestResult<T>>;
