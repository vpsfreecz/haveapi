# Generated API documentation examples

The Ruby server can show Go examples for a configured generated SDK. Install the
optional `haveapi-go-client` generator gem alongside the server gem. Register the
profile before mounting the API:

```ruby
api.documentation_clients('7',
  go: { import_path: 'example.org/widget-sdk/v2/client' }
)
api.mount('/api/')
```

`import_path` identifies the SDK package, including its package subdirectory.
Examples use the explicit import alias `client`. `generator_version` defaults
to the server's `HaveAPI::VERSION` and must match the installed generator gem.
An explicit value requires the installed generator to report that version. It
does not select the SDK version or download a generator.

`module_version` is optional. Omission or nil renders
`go get example.org/widget-sdk/v2/client@latest`; `module_version: 'v2.3.4'`
selects that version instead. Go resolves latest by its normal rules and existing
module configuration still applies. Latest can change over time. The server
never queries a package registry or claims to have resolved the installed SDK.

At the end of mount, the server builds one private structural model per
configured API version from the complete declaration, including authentication
routes and changes from post-mount hooks. The copy excludes prose, examples and
parameter defaults; canonical names still include every sibling and ancestor.
Requests use the current user's authorized help and samples. The configured SDK
is expected to match this generation contract. Its package name or version does
not prove that match; older SDKs can lack actions or use different collision names.

For an older or deliberately restricted SDK, add
`description_path: '/etc/widget-api/sdk-v7.json'`. This optional trusted absolute
JSON file contains the complete description used to generate that SDK, including
siblings, aliases and authentication descriptions. Retain it with the SDK; do
not reconstruct it from a filtered documentation page. The description has no
API-version field, so the profile's version key binds it to the selected version.
Keep saved descriptions private because they can contain privileged information.
The prior explicit `module_version`/`description_path`/`generator_version` form
remains supported.

A missing profile hides Go everywhere. Unknown fields, invalid profiles, missing
files and actual generator-version mismatches fail startup. Saved descriptions
are loaded during registration; automatic adapters are initialized at the end of
mount. No profiles are published when mount fails. HTML requests read no files,
fetch no descriptions and run no generator, compiler or formatter. Removing the
profile changes documentation availability without changing API wire behavior.
See the [server profile guide](../../../doc/client-examples.md) for configuration,
compatibility assumptions and rollback requirements.

## Mapping and supported samples

`HaveAPI::GoClient::Documentation` constructs the generator's `ApiVersion` from
the complete private description, whether automatic or saved. Resource and
action members, including aliases and collision suffixes, come from the
generator's existing name allocator. The current user's filtered server
description controls which samples and fields can appear. A saved SDK description
can lag unrelated server additions. Each rendered sample must still match its
route, input and output layouts, and supplied field contracts.
Unsupported or stale samples show a short limitation instead of incomplete code.

Programs initialize the client with the API origin. Saved action paths include
the mounted root and selected `/vVERSION/` segment. Ordered sample path arguments
become the generated `SetPathParamInt` or `SetPathParamString` calls. Object/hash
input uses `NewInput().SelectParameters()` before setters; this preserves omitted fields,
explicit zero, false and empty strings. Nullable fields use `SetFIELDNil(true)`.
An empty request selects no fields. A missing request leaves input unallocated.

Simple action examples assume that initialization and authentication have
established `api`. They show the invocation, supplied values, error checks and
sample output. Add `fmt` to the enclosing program's imports for output and error
messages. **With error handling** includes the complete program and advertised
metadata guidance. Both levels validate the same sample and report the same limitations.

List input and general Custom fields are unsupported by the generator and show
limitations. Global input metadata has the existing `includes` Custom exception:
its generated setter accepts a string. Metadata guidance only names methods
advertised by the filtered description. It shows `NewMetaInput().SelectParameters()`
before setters without inventing a metadata payload for an action sample.
Samples requiring global or object input metadata show a limitation because the
example DSL cannot supply metadata values.

Object/hash and list outputs are supported. Examples access only fields present
in the sample, iterate list output and guard optional objects. Associated values
must be objects or null; nested fields require a matching visible associated
`show` action. Scalar Go output fields cannot distinguish null from their zero
value, so samples requiring that distinction show a limitation.

Transport or validation errors and unsuccessful API responses have separate
branches. Basic authentication and existing token/OAuth2 authentication use
environment variables for credentials. OAuth2 access-token acquisition happens
through the provider before running the example. A blocking action can show
`IsBlocking` and `OperationStatus` only when the visible action-state route,
metadata and the generated helper's fixed member names match. Request success
does not establish operation completion.

## Pure adapter and offline generation

The documentation adapter accepts loaded data and returns frozen plain results:

```ruby
adapter = HaveAPI::GoClient::Documentation.new(
  description: full_description,
  import_path: 'example.org/widget-sdk/v2/client',
  module_version: nil # Optional; use 'v2.3.4' to select a version.
)
resolved = adapter.resolve(resource_path: %w[widget], action_name: 'update')
result = adapter.render(kind: :example, context: context, mode: :sync)
```

The context uses readers defined by the server's documentation context. The
adapter does not depend on the server gem. Results have either
`{status: :code, code: source}` or `{status: :limitation, reason: text}`. The context
must expose `detail` as `:simple` or `:thorough`. Renderers
return source/plain text; the server template escapes HTML once.

For SDK fixtures or an already captured schema, use the offline constructor.
It preserves the ordinary URL constructor's generation options:

```ruby
generator = HaveAPI::GoClient::Generator.from_description(
  saved_description,
  destination,
  module: 'example.org/widget-sdk/v2',
  package: 'client'
)
generator.generate
generator.go_fmt
```

Construction performs no discovery or writes. Generation and formatting are
explicit operations; the documentation adapter never calls them.

## Verification

From the repository root, with the Go and Ruby server bundles prepared:

```sh
HAVEAPI_RELEASE_TOOLS_ONLY=1 nix develop -c bash -c \
  'BUNDLE_GEMFILE="$PWD/clients/go/Gemfile" bundle exec rspec \
    -I clients/go/lib clients/go/spec/unit/documentation_spec.rb'
HAVEAPI_RELEASE_TOOLS_ONLY=1 nix develop -c bash -c \
  'BUNDLE_GEMFILE="$PWD/servers/ruby/Gemfile" bundle exec rspec \
    -I servers/ruby/lib servers/ruby/spec/client_examples/go_spec.rb'
```

These pure checks cover canonical names, aliases, collisions, visibility,
input/output fidelity, source escaping and unsupported capabilities. They do not
start a server or compile Go. The separate acceptance harness uses its own bundle
so both the server and optional generator gems are activated, along with WEBrick:

```sh
HAVEAPI_RELEASE_TOOLS_ONLY=1 nix develop -c bash -c \
  'BUNDLE_GEMFILE="$PWD/clients/go/spec/documentation.Gemfile" bundle check'
```

If dependencies need installation, run `bundle install` with that same
`BUNDLE_GEMFILE` in the Nix shell. Check profile loading without starting a server
or compiling Go:

```sh
HAVEAPI_RELEASE_TOOLS_ONLY=1 nix develop -c bash -c \
  'BUNDLE_GEMFILE="$PWD/clients/go/spec/documentation.Gemfile" bundle exec ruby \
    clients/go/spec/documentation_acceptance.rb --check-environment'
```

The temporary consumer has no repository history. Its build uses
`-buildvcs=false` so an ancestor Git directory cannot supply unrelated metadata
or prevent compilation. This setting applies only to the disposable documentation
consumer. Record the tested source and retained artifacts in verification receipts.

Check the build command with an owned invalid Git ancestor, without running a
compiler or listener:

```sh
HAVEAPI_RELEASE_TOOLS_ONLY=1 nix develop -c bash -c \
  'BUNDLE_GEMFILE="$PWD/clients/go/spec/documentation.Gemfile" bundle exec ruby \
    clients/go/spec/documentation_build_check.rb'
```

Run the complete acceptance harness:

```sh
HAVEAPI_RELEASE_TOOLS_ONLY=1 nix develop -c bash -c \
  'BUNDLE_GEMFILE="$PWD/clients/go/spec/documentation.Gemfile" bundle exec ruby \
    clients/go/spec/documentation_acceptance.rb'
```

The harness saves a local schema fixture, generates its SDK and loads the matching
profile. It checks both detail levels, composing simple action fragments with
separately rendered initialization or authentication.
It formats, compiles and runs those programs against a disposable localhost
server. Cases include initialization, authentication methods, mounted/versioned
paths, nullable/false/zero/omitted inputs, list output, failures, global metadata
and action state. Go dependency and toolchain downloads are disabled. Generated
Go files remain disposable generator outputs.
