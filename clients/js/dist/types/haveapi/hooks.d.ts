import type { DoneCallback } from './client';
interface HookEntry {
    done: boolean;
    arguments: unknown[];
    callables: DoneCallback[];
}
export interface Hooks {
    debug: number;
    hooks: Record<string, Record<string, HookEntry>>;
    register(type: string, event: string, callback: DoneCallback): void;
    invoke(type: string, event: string, ...args: unknown[]): void;
}
export interface HooksConstructor {
    new (debug?: number): Hooks;
    prototype: Hooks;
}
/**
 * @class Hooks
 * @memberof HaveAPI.Client
 */
export declare const Hooks: HooksConstructor;
export {};
