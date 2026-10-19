import { AsyncResourceInstance } from './resource_instance';
import { hasOwn, nonThenable, pathParams, snapshotValues } from './resource';
import type { Values } from '../types';
import type { AsyncResourceContext, RequestResult } from './types';

/** Local list operations never issue a request or return callback-owned objects. */
export class AsyncResourceList implements Iterable<AsyncResourceInstance> {
	readonly [index: number]: AsyncResourceInstance;
	readonly then!: undefined;
	readonly items: readonly AsyncResourceInstance[];
	readonly length: number;
	readonly totalCount: unknown;
	declare [Symbol.iterator]: () => IterableIterator<AsyncResourceInstance>;

	constructor(context: AsyncResourceContext, path: readonly string[], response: RequestResult<unknown>) {
		if (!Array.isArray(response.data))
			throw context.makeError('protocol', 'Expected an object-list response', {response});
		const items = response.data.map(value => {
			if (!value || typeof value !== 'object' || Array.isArray(value))
				throw context.makeError('protocol', 'Malformed object-list item', {response});
			const data = snapshotValues(context, value as Values);
			const meta = hasOwn(data, context.metaNamespace) ? data[context.metaNamespace] : {};
			if (!meta || typeof meta !== 'object' || Array.isArray(meta))
				throw context.makeError('protocol', 'Malformed object metadata', {response});
			return new AsyncResourceInstance(context, path, data, pathParams(context, meta as Values) || [], true);
		});
		this.items = Object.freeze(items);
		this.length = items.length;
		items.forEach((item, index) => Object.defineProperty(this, String(index), {value: item, enumerable: true}));
		this.totalCount = response.meta.total_count;
		nonThenable(this);
		// Resolve Symbol only when an async list is constructed. Legacy-only
		// bundle loading retains its original runtime requirements.
		Object.defineProperty(this, Symbol.iterator, {value: () => this.items[Symbol.iterator]()});
	}

	itemAt(index: number): AsyncResourceInstance | undefined { return this.items[index]; }
	first(): AsyncResourceInstance | null { return this.items[0] || null; }
	last(): AsyncResourceInstance | null { return this.items[this.length - 1] || null; }
	each(fn: (item: AsyncResourceInstance, index: number) => void): void { this.items.forEach(fn); }
}
