import type { ActionDescription } from '../types';
import type { AsyncResourceContext, CompletionOptions, CompletionResult, InvocationResult } from './types';
export interface InvocationRecord {
    context: AsyncResourceContext;
    action: ActionDescription;
    stateId: unknown;
}
export declare function waitForCompletion<T>(result: InvocationResult<T>, record: InvocationRecord | undefined, options: CompletionOptions): Promise<CompletionResult<T>>;
