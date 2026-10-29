import type { AuthenticationRegistry } from "./authentication";
import type { Params } from "./types";

interface LegacyGlobals {
  Authentication: AuthenticationRegistry;
  v1: string[];
  v2: string[];
  ret: Params;
}

declare const global: LegacyGlobals;

// These four callback-era globals remain observable even when a consumer wraps
// the UMD in strict code. Read their properties live rather than caching values.
// Older browser, worker and Node hosts need no globalThis polyfill.
export const legacyGlobals = (typeof globalThis !== "undefined"
  ? globalThis
  : typeof window !== "undefined"
    ? window
    : typeof self !== "undefined"
      ? self
      : global) as unknown as LegacyGlobals;
