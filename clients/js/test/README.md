# JavaScript client checks

Run commands from the repository's `nix develop .#client-js` environment.
The build owner regenerates `dist/haveapi-client.js` and `dist/types` before
checking converted source. Do not edit those outputs directly.

From `clients/js`, prepare dependencies first:

```sh
npm install --no-audit --no-fund
```

This creates or reuses the ignored local `package-lock.json`. Run the build and
checks against that prepared resolution without installing dependencies between
them. The compatibility suite also inspects this local dependency graph.

## Build tool compatibility

Fresh dependency preparation can select different compatible versions within
the constraints in `package.json`.

The pinned Node 24 shell builds the client with TypeScript 6.0.3 and Rollup.
TypeScript 6 supports the bundle's ES5 target; TypeScript 7 removes it. The
affected build and consumer configs set `ignoreDeprecations: "6.0"` for ES5 and
`moduleResolution: "node"`, the legacy Node10 resolution algorithm. Strict type
and declaration checks and an ES5 parser still validate the emitted package.
The async client's runtime requirements remain unchanged.

JSDoc uses `markdown-it` 15.0.3 and `markdown-it-anchor` 10.0.0 through overrides
scoped to JSDoc. The compatibility suite checks heading renders, links and
generated API navigation. These are build tools; package consumers use the
bundled JavaScript and emitted declarations.

## Check commands

The focused checks are:

```sh
npm run typecheck
npm run build
npm run test:compatibility
npm run test:async
npm run test:resources
npm run test:types
```

The resource and async declaration configs inherit the compiler settings above.
`@types/node` stays on the Node 24 line used by the development shell.

The compatibility suite parses the distributed bundle as ES5 and tests its
bundled TypeScript helpers with conflicting global helper names. The callback
client loads without Promise, AbortController or globalThis; async operations
require their documented modern runtime features. The bundle includes helpers
from tslib's ES5-compatible ESM entry and its license notice. Installed consumers
do not need tslib or the build dependencies. The dependency-graph check uses the
build's Rollup input configuration and rejects circular dependencies and
top-level `this` rewrites. Normal builds report warnings without filtering them.

`npm run test:compatibility` also generates documentation in a temporary
directory and checks the Client, Action and Resource pages, navigation and
the existing Action `invoke__anchor` link. JSDoc uses its maintained default
template. The compatibility anchor sits beside the canonical `invoke` heading;
generation fails if that heading is missing or another element uses the alias.
`jsdoc_markdown.spec.cjs` uses JSDoc's Markdown renderer with the scoped
`markdown-it` 15.0.3 and `markdown-it-anchor` 10.0.0 overrides. It checks repeated
headings across separate renders, inline JSDoc links, fenced code, heading anchors
and bare-URL behavior. These checks cover the interface between JSDoc and its
Markdown plugins.

Generate the full documentation under `html_doc` with:

```sh
./node_modules/.bin/gulp doc
```

The callback compatibility fixture uses Node's built-in test runner and fake XHR
responses. It needs no API server or additional test dependencies:

```sh
node --test clients/js/test/compatibility/callback.spec.cjs
```

It exercises the distributed bundle through CommonJS, browser-global and AMD
loaders, with Promise and AbortController absent. It checks callback timing and
arguments, undefined returns, synchronous throws, hooks, callable resource/action
prototypes, metadata, list helpers and attribute descriptors. Hook receiver and
argument assertions preserve the existing implementation, including its quirks;
they do not specify the new AsyncClient contract.

`test/compatibility/mounted_paths.spec.cjs` covers callback and async descriptor
paths, raw requests, discovery, global/versioned token challenges and state
polling without a listener. The server's
`spec/client_examples/dynamic_mounted_paths_spec.rb` also feeds actual mounted
Rack descriptions and token/action replies through the built clients.

The initial 12 cases passed before conversion against the bundle at
`cb3f39f75e8a63416388d24293f936d1db97162b`, SHA-256
`3e8fcefe8edf78f6cea635c1bf4312b56c2e05355287153e142d30a9608c6436`.
The same cases must pass against the converted bundle. The original bundle is
available from Git history; a second tracked copy is unnecessary.

The strict-context fixture checks the same distributed artifact inside a strict
CommonJS wrapper, as used when a browser bundler embeds it in a module:

```sh
node --test clients/js/test/compatibility/strict_context.spec.cjs
```

It compares raw and strict callback loading, setup, version checks and
`defaultParams`, including the existing `Authentication`, `v1`, `v2` and `ret`
global effects and live reads. The `window`, `self` and `global` host fallbacks
run with `globalThis`, Promise and AbortController absent. The `self` case uses
fake CommonJS XHR and checks host lookup; it does not certify worker transport.
This VM check complements actual minified browser-package import verification.

The TypeScript fixture compiles against generated package declarations rather
than authored source:

```sh
cd clients/js
./node_modules/.bin/tsc -p test/types/callback.tsconfig.json
```

Its positive examples cover callback overloads, callable resources/actions and
typed response payloads. Its expected errors reject Promise returns from Client,
missing callbacks and endpoint names that have no application-supplied schema.
Type checking cannot infer resource names from a runtime API description.

These local fixtures do not verify a server or browser implementation. The Mocha
suite includes Ruby-server contract tests and requires the matching Ruby
environment. Run longer server/browser verification through the workspace's
verification workflow after final review.

The async-resource unit suite checks the resource layer independently of the
client's transport/authentication implementation. Its test-only CommonJS emit
is stored under ignored `test/tmp/async-resources`:

```sh
cd clients/js
./node_modules/.bin/tsc -p test/async-resources.tsconfig.json
node --test test/async_resources/resource.spec.cjs
```

The suite covers immutable concurrent IDs/options, local getters and iteration,
nonthenable name collisions, save publication and accepted-unbound protection,
explicit association loading, abort forwarding and generation-bound sends.
It imports only the async resource modules from that private test emit. Legacy
callback modules require the final non-strict bundle and are checked through
that artifact. `test/types/async.tsconfig.json` checks async examples against the
emitted package declarations. The shared Ruby-server contract file runs both
`CallbackAdapter` and `AsyncAdapter`; do not run it as a quick unit check.

`test/async/resource_save.spec.cjs` also exercises the built bundle with actual
parameter validation and fake XHR. It checks Resource-valued create/save inputs,
association identifier selection, dispatch snapshots and duplicate-create
protection after a validated successful response cannot be materialized. It runs
with the other bundle fixtures through `npm run test:async`; no API server is
required.
