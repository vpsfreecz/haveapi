# Generated TypeScript documentation examples

The Ruby server can show examples for a generated TypeScript SDK alongside its
dynamic TypeScript clients. The generated examples use the SDK's public
`createClient` factory and `haveapi-client` version `0.30.2` for requests and
authentication. The server prepares the SDK model at mount time and renders
examples when users view the documentation.

## Configure the SDK profile

Register the profile for the same API version as the SDK:

```ruby
api.documentation_clients('1.0',
  typescript: {
    package_name: '@example/widget-client',
    package_version: '1.2.3',
    snapshot_path: '/absolute/path/to/widget-client/schema.json'
  }
)
api.mount('/mount/')
```

`package_name` is an ordinary scoped or unscoped npm package name.
`package_version` is optional and accepts a concrete SemVer, without ranges or
tags. Omitting it leaves package-version selection to the package manager; it
does not prove the package is available. Configure a package that users can
install through its supported distribution channel.

An optional `snapshot_path` selects the exact saved schema used for the SDK.
Without it, the server builds the adapter from its complete mounted declaration.
This private description excludes all defaults, prose and samples. An optional
`generator_version` must match the installed generator version.

The generator is an optional server dependency. Invalid profile fields, missing
generator code, unreadable or invalid snapshots and version mismatches reject
startup without publishing partial profiles. The profile accepts package identity,
snapshot and generator-version settings. Configure authentication in the client
runtime. Existing dynamic TypeScript examples remain separate.

## Rendered calls and compatibility

Examples bind the selected API version URL directly:

```ts
import {AsyncClient} from 'haveapi-client';
import {createClient} from '@example/widget-client';

const runtime = new AsyncClient('https://api.example.test/mount/v1.0');
const api = createClient({execute: spec => runtime.request(spec)});
```

The version and mount belong in the runtime's base URL. Its constructor `version`
option does not prefix raw requests. Public examples need no setup. Protected
examples use the runtime's Basic authentication or an existing HaveAPI token,
with credentials read from `HAVEAPI_USER`, `HAVEAPI_PASSWORD` or `HAVEAPI_TOKEN`.
Both the saved SDK and current authorized help must advertise the provider;
token header names must agree. Token acquisition, renewal and OAuth are outside
this adapter.

The adapter resolves names and aliases from a frozen SDK model. It then checks
the current user's help, action and filtered sample. Changed routes, methods,
versions, layouts, namespaces or used field contracts produce a limitation.
Hidden fields and defaults are not filled from the private model. Unrelated
optional additions do not prevent a compatible example.

Samples use the existing example DSL. Path arguments follow its declared order;
input wire names map to generated input names. The DSL has no separate input
metadata carrier, so actions requiring input metadata produce a limitation.
Inputs preserve omission, null, false, zero and empty strings. Unsafe integer IDs,
invalid JSON and structured Custom query values cannot be rendered. Output keys
remain wire names, with guards for optional, null and unknown values.

Successful examples retain `data`, `meta`, `envelope` and `httpStatus`. Rejection
examples inspect the runtime's error receipt without printing server diagnostics.
Requests are not retried. A successful request does not establish completion of
a server-side operation; raw receipts cannot be passed to `waitForCompletion`.

## Adapter and checks

The generator provides `HaveAPI::TypeScriptClient::Documentation` through
`require 'haveapi/typescript_client/documentation'`. Its factories accept a full
description or saved snapshot. `resolve` returns a frozen canonical action;
`render` returns the server's code or limitation result. Rendering performs no
file, network, generator or compiler work.

Rendering selects the current action, authentication provider and metadata
namespace before recursively normalizing their contents. It leaves unrelated
description descendants untouched and keeps authorization decisions local to
each render. Deterministic work checks grow unrelated subtrees while keeping
the selected inputs and rendered source fixed.

Focused unit checks compile the actual rendered programs against generated
fixture modules with TypeScript 6, NodeNext/ES2022, `exactOptionalPropertyTypes`,
`noUncheckedIndexedAccess` and `verbatimModuleSyntax`. They cover aliases, nested
paths, filtered fields, stale contracts, supported authentication and errors.

Run the wire harness with a prepared published `haveapi-client@0.30.2`
installation:

```sh
HAVEAPI_TYPESCRIPT_RUNTIME=/absolute/path/to/haveapi-client/dist/haveapi-client.js \
  HAVEAPI_RELEASE_TOOLS_ONLY=1 nix develop --command bundle exec ruby \
  clients/typescript/spec/documentation/wire.rb
```

The harness verifies the runtime artifact's hash, compiles the rendered snippets,
and runs them against a local server at root and mounted URLs. It checks exact
requests, Basic and existing-token routing, aliases, nested IDs and rejection
handling. It downloads no runtime and calls no production API.
