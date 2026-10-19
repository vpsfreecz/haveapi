import type { AuthenticationRegistry } from './authentication';
import type { Params } from './types';
interface LegacyGlobals {
    Authentication: AuthenticationRegistry;
    v1: string[];
    v2: string[];
    ret: Params;
}
export declare const legacyGlobals: LegacyGlobals;
export {};
