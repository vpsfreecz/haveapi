import type { ActionDescription, Credentials, Description, HeaderMap, Language, Params } from '../types';
import type { AsyncAuthenticationOptions, RequestResult, RequestSpec } from './types';
export interface AuthenticationState {
    headers: HeaderMap;
    credentials?: Credentials;
}
export declare function validateParams(action: ActionDescription, params: Params | undefined, language: Language): Params;
export declare function descriptionSnapshot(value: unknown, baseUrl: string): Description;
export declare function checkProtocol(result: RequestResult<unknown>): void;
export declare function authenticate(method: string, options: AsyncAuthenticationOptions, description: Description, send: <T>(spec: RequestSpec, state: AuthenticationState) => Promise<RequestResult<T>>, language: Language): Promise<AuthenticationState>;
