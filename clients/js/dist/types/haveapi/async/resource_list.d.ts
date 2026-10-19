import { AsyncResourceInstance } from './resource_instance';
import type { AsyncResourceContext, RequestResult } from './types';
/** Local list operations never issue a request or return callback-owned objects. */
export declare class AsyncResourceList implements Iterable<AsyncResourceInstance> {
    readonly [index: number]: AsyncResourceInstance;
    readonly then: undefined;
    readonly items: readonly AsyncResourceInstance[];
    readonly length: number;
    readonly totalCount: unknown;
    [Symbol.iterator]: () => IterableIterator<AsyncResourceInstance>;
    constructor(context: AsyncResourceContext, path: readonly string[], response: RequestResult<unknown>);
    itemAt(index: number): AsyncResourceInstance | undefined;
    first(): AsyncResourceInstance | null;
    last(): AsyncResourceInstance | null;
    each(fn: (item: AsyncResourceInstance, index: number) => void): void;
}
