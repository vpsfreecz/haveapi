import type { ActionDescription, Description, Envelope, HeaderMap, Meta, Params, Values, ValidationErrors } from '../types';
import type { AsyncError } from './error';
export type AsyncErrorKind = 'validation' | 'transport' | 'protocol' | 'authentication' | 'api' | 'action-failed' | 'timeout' | 'aborted';
export interface RequestSpec {
    method: string;
    path: string;
    inputNamespace?: string | null;
    outputNamespace?: string | null;
    metaNamespace?: string;
    params?: Params;
    meta?: Meta;
    headers?: HeaderMap;
    signal?: AbortSignal;
    timeoutMs?: number;
}
export interface RequestResult<T = unknown> {
    data: T;
    meta: Meta;
    envelope: Envelope;
    httpStatus: number;
}
export interface InvocationResult<T = unknown> {
    value: T;
    response: RequestResult<unknown>;
}
export interface ActionStateSnapshot {
    id: number;
    label?: string;
    finished: boolean;
    status: boolean;
    canCancel: boolean;
    progress: {
        current: number;
        total: number;
        unit?: string;
    };
    createdAt?: string | null;
    updatedAt?: string | null;
}
export interface AsyncErrorDetails {
    httpStatus?: number;
    response?: RequestResult<unknown>;
    envelope?: Envelope;
    errors?: ValidationErrors;
    state?: ActionStateSnapshot;
    cause?: unknown;
    reason?: string;
}
/** Internal binding seam; resources receive a validated, generation-bound snapshot. */
export interface AsyncResourceContext {
    readonly description: Description;
    readonly metaNamespace: string;
    readonly generation: number;
    request<T = unknown>(spec: RequestSpec): Promise<RequestResult<T>>;
    validateParams(action: ActionDescription, params?: Params): Params;
    makeError(kind: AsyncErrorKind, message: string, details?: AsyncErrorDetails): AsyncError;
    recordInvocation<T>(value: T, response: RequestResult<unknown>, action: ActionDescription): InvocationResult<T>;
}
export interface CompletionOptions {
    timeoutMs: number;
    signal?: AbortSignal;
    blockInterval?: number;
    blockUpdateIn?: number;
    onStateChange?: (state: ActionStateSnapshot) => void;
}
export interface CompletionResult<T> extends InvocationResult<T> {
    state: ActionStateSnapshot | null;
}
export interface AsyncAuthenticationOptions extends Values {
    user?: string;
    password?: string;
    token?: string;
    validTo?: string;
    lifetime?: string;
    interval?: number;
    access_token?: {
        access_token: string;
        refresh_token?: string;
        expires?: number;
    };
    onChallenge?: (action: string, parameters: Values) => Params | PromiseLike<Params>;
}
