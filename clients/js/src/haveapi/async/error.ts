import type { AsyncErrorDetails, AsyncErrorKind, RequestResult, ActionStateSnapshot } from './types';
import type { Envelope, ValidationErrors } from '../types';

export class AsyncError extends Error implements AsyncErrorDetails {
	readonly kind: AsyncErrorKind;
	httpStatus?: number;
	response?: RequestResult<unknown>;
	envelope?: Envelope;
	errors?: ValidationErrors;
	state?: ActionStateSnapshot;
	cause?: unknown;
	reason?: string;

	constructor(kind: AsyncErrorKind, message: string, details: AsyncErrorDetails = {}) {
		super(message);
		Object.setPrototypeOf(this, AsyncError.prototype);
		this.name = kind === 'aborted' ? 'AbortError' : 'AsyncError';
		this.kind = kind;
		// Only supported diagnostic fields are copied; request credentials never are.
		(['httpStatus', 'response', 'envelope', 'errors', 'state', 'cause', 'reason'] as const).forEach(key => {
			if (Object.prototype.hasOwnProperty.call(details, key))
				Object.defineProperty(this, key, {value: details[key], writable: true, enumerable: true, configurable: true});
		});
	}
}

export function asAsyncError(error: unknown, kind: AsyncErrorKind = 'protocol'): AsyncError {
	return error instanceof AsyncError ? error : new AsyncError(kind,
		error instanceof Error ? error.message : String(error), {cause: error});
}
