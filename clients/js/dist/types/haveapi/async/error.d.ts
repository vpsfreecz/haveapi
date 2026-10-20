import type { ApiErrors, AsyncErrorDetails, AsyncErrorKind, RequestResult, ActionStateSnapshot } from './types';
import type { Envelope } from '../types';
export declare class AsyncError extends Error implements AsyncErrorDetails {
    readonly kind: AsyncErrorKind;
    httpStatus?: number;
    response?: RequestResult<unknown>;
    envelope?: Envelope<unknown, ApiErrors>;
    errors?: ApiErrors;
    state?: ActionStateSnapshot;
    cause?: unknown;
    reason?: string;
    constructor(kind: AsyncErrorKind, message: string, details?: AsyncErrorDetails);
}
export declare function asAsyncError(error: unknown, kind?: AsyncErrorKind): AsyncError;
