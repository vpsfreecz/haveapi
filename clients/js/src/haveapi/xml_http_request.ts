import type { LegacyXMLHttpRequestConstructor } from './types';

// The UMD factory captures the host binding before Rollup's export container.
declare const haveapiCommonJS: boolean;
declare function require(name: string): {XMLHttpRequest: LegacyXMLHttpRequestConstructor};

// Keep the existing browser/CommonJS selection. The dependency remains inside
// this branch so browser script loading never requires a module loader.
var XMLHttpRequest: LegacyXMLHttpRequestConstructor;
if (haveapiCommonJS && (typeof window === 'undefined' || !window.XMLHttpRequest)) {
	XMLHttpRequest = require('xmlhttprequest').XMLHttpRequest;
} else {
	XMLHttpRequest = window.XMLHttpRequest as unknown as LegacyXMLHttpRequestConstructor;
}
export { XMLHttpRequest };
