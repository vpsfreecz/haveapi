# TypeScript client generator

Generate a typed TypeScript client for one API version from a saved HaveAPI
protocol 2 schema. Call resources and actions by name, with types for their
arguments and results. A request executor connects those calls to the existing
`haveapi-client` runtime or your application's adapter.

## Install the generator

The generator is packaged as the Ruby gem `haveapi-typescript-client`. Once a
release containing the generator and shared schema API is available, install it
with:

```sh
gem install haveapi-typescript-client
```

The packaged command is `haveapi-typescript-client`; it accepts the same `fetch`
and `generate` arguments shown below. Its Ruby `haveapi-client` dependency must
contain the shared schema API. An older gem in the same version range is not
sufficient. For unreleased development source, use the checkout setup below.
See the [release guide](../../doc/agent-instructions/releases.md) for coordinated
packaging and trusted-publisher setup.

## Prepare the source tools

The generator requires Ruby 3.2 or newer. From the HaveAPI checkout root:

```sh
nix develop
BUNDLE_GEMFILE="$PWD/clients/typescript/Gemfile" bundle install
```

The component bundle uses the Ruby client from the same checkout. Record the
checkout revision and resolved dependency inputs. Generation reads local files
using the prepared dependencies and runs without contacting the API.

Applications need a TypeScript compiler and the `haveapi-client` JavaScript
runtime. The supported runtime version is exactly `0.30.2`.

## Fetch, save and generate

The example API at `https://example.test/api/v1.0/` has `Widget#Update` at
`/api/v1.0/widgets/{widget_id}`, a nullable string `name` input and an integer
`id` output. Replace the example URL, version and resource names with those of
your API.

From the HaveAPI root:

```sh
mkdir -p /path/to/widget-client/schema
BUNDLE_GEMFILE="$PWD/clients/typescript/Gemfile" bundle exec ruby \
  clients/typescript/bin/haveapi-typescript-client fetch https://example.test/api/v1.0/ \
  --api-version 1.0 --profile public \
  --output /path/to/widget-client/schema/api.json
BUNDLE_GEMFILE="$PWD/clients/typescript/Gemfile" bundle exec ruby \
  clients/typescript/bin/haveapi-typescript-client generate \
  --schema /path/to/widget-client/schema/api.json --api-version 1.0 \
  --output /path/to/widget-client/src/generated
BUNDLE_GEMFILE="$PWD/clients/typescript/Gemfile" bundle exec ruby \
  clients/typescript/bin/haveapi-typescript-client generate \
  --schema /path/to/widget-client/schema/api.json --api-version 1.0 \
  --output /path/to/widget-client/src/generated --check
```

The saved schema's parent directory must already exist. Fetch uses the exact
version URL, including its mount prefix; it does not select a server default.
The explicit generation version must match the saved snapshot. `--check` reports
missing or stale output without changing it. Keep handwritten files outside
`src/generated`.

For Basic capture, set `WIDGET_PASSWORD` in your environment, then run:

```sh
BUNDLE_GEMFILE="$PWD/clients/typescript/Gemfile" bundle exec ruby \
  clients/typescript/bin/haveapi-typescript-client fetch https://example.test/api/v1.0/ \
  --api-version 1.0 --profile basic-user --basic-user demo \
  --basic-password-env WIDGET_PASSWORD \
  --output /path/to/widget-client/schema/api.json
```

For an existing HaveAPI token, set `WIDGET_TOKEN` and run:

```sh
BUNDLE_GEMFILE="$PWD/clients/typescript/Gemfile" bundle exec ruby \
  clients/typescript/bin/haveapi-typescript-client fetch https://example.test/api/v1.0/ \
  --api-version 1.0 --profile token-user --token-env WIDGET_TOKEN \
  --output /path/to/widget-client/schema/api.json
```

The two authentication choices are mutually exclusive. Token capture first reads
anonymous discovery at the same version endpoint, then uses the advertised token
header. Supply a token you have already acquired. `--profile` labels the capture;
it does not change authentication. Permissions and enabled plugins determine
which resources the snapshot contains. Failed capture preserves an existing
output file.

## Use the generated client

In the application containing the generated files, install the supported runtime
and a TypeScript compiler:

```sh
cd /path/to/widget-client
npm install --save-exact haveapi-client@0.30.2
npm install --save-dev typescript
```

Import the local generated entry point:

```ts
import { AsyncClient } from 'haveapi-client';
import { createClient } from './src/generated/index.js';

const runtime = new AsyncClient('https://example.test/api/v1.0');
const api = createClient({ execute: spec => runtime.request(spec) });

const result = await api.widget.update({
  path: { widget_id: 1 },
  params: { name: 'new name' },
});
console.log(result.data.id);
```

The executor's base URL includes the mount and API version. Do not add a
constructor version option: raw `request` calls already use this versioned base.
Configure authentication through the runtime or your application's adapter;
generated authentication actions are excluded and permissions still apply.

Pass action arguments in one options object: `path` for resource IDs, `params`
for input fields, and `meta` for metadata. The same object accepts request
headers, a timeout and an abort signal. Results contain typed `data`, metadata,
the response envelope and HTTP status. Runtime errors reject the promise.
Raw request results cannot be passed to
`AsyncClient.waitForCompletion`; see the
[JavaScript runtime guide](../js/README.md#advanced-usage-and-reference).

## Schemas and types

Input is a format 1 snapshot with `api_version`, `protocol_version` (major 2),
`source_url`, `profile`, `mount_path` and `description`. The description includes
application resources, authentication discovery, the metadata namespace and
versioned routes. The source URL records where the schema came from and is never
contacted during generation. See the
[snapshot reference](../../doc/agent-instructions/development.md#typescript-snapshots-and-provenance)
for the format and capture helper.

A snapshot covers the resources visible to its capture profile and plugins.
Server permissions and validation still apply when you call an action. Review
snapshots before sharing them; they must not contain credentials or tokens.
Unsupported schema shapes, unsafe routes and name collisions stop generation
before output is written. These include input lists, Custom IO formats and
GET/OPTIONS actions with object-input metadata.

- Omitted input fields stay omitted. Nullable `null`, `false`, zero and empty
  strings are preserved. Numeric integers and path IDs must be JavaScript safe
  integers; path strings are also supported. Datetime values remain strings.
- Custom body input accepts JSON. Custom query input accepts only scalars.
- Output fields can be absent or null; associations are partial records and
  Custom output is `unknown`. Generated types do not validate response data.

## Generated files and regeneration

Browse resource and action types in their own modules:

```text
src/generated/
  index.ts
  api.ts
  runtime.ts
  types.ts
  resources/
    widget/
      resource.ts
      actions/
        update.ts
      resources/
        child/
          resource.ts
```

Import from `index.ts` in application code. Resource directories and action
filenames follow the generated accessor names; aliases share their canonical
action's module. Individual module paths are not stable package exports.

The generator owns the entire `src/generated` directory and records its files in
`.haveapi-generated.json`. Regeneration replaces owned files and removes stale
output, including nested directories. It refuses symlinks and foreign files.
Commit the whole generated tree and manifest together. Regenerate with the
recorded schema and HaveAPI revision, and keep that generator/client pair
together when reverting versions.

An interrupted write can leave mixed output. Restore the committed generated
tree before regenerating. If the first generation was interrupted before an
ownership manifest was written, preserve that partial directory and generate
into a fresh empty `src/generated`. Do not edit the manifest to bypass a refusal.

The Ruby server can render examples using this generated interface; see
[generated documentation profiles](docs/documentation.md).

## Development

See [generator development](../../doc/agent-instructions/development.md#typescript-generator)
for contributor setup, checks and implementation contracts.
