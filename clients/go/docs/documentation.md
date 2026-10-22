# Generated API documentation examples

The Ruby server can show Go examples for a configured generated SDK. The SDK's
module version is independent of the HaveAPI gem version and API version.
Install the `haveapi-go-client` gem at the exact generator version used for the
SDK, alongside the server gem. Configure the profile before mounting the API:

```ruby
api.documentation_clients(
  '7',
  go: {
    import_path: 'example.org/widget-sdk/v2/client',
    module_version: 'v2.3.4',
    description_path: '/etc/widget-api/sdk-v7.json',
    generator_version: '0.30.0'
  }
)
```

`import_path` identifies the published SDK package, including its package
subdirectory. Examples import it with the explicit alias `client`. The local
absolute JSON file must contain the complete description used to generate that
SDK, including sibling resources, aliases and authentication descriptions.
Retain this file with the SDK release; do not create it from a filtered public
documentation page. The Go description has no API-version field. The configuration's version key
binds the retained description to that API version.
Keep the description private because it can include privileged API information.

A missing profile hides the Go overview entry and all Go example panels. An
invalid profile or a missing or mismatched generator gem fails configuration.
The server loads the file and constructs the adapter during configuration. HTML
requests do not read files, fetch API descriptions, generate source, invoke Go
or write an SDK. Removing the profile disables Go examples without changing API
behavior or existing clients.

## Mapping and supported samples

`HaveAPI::GoClient::Documentation` constructs the generator's `ApiVersion` from
the full saved description. Resource and action members, including aliases and
collision suffixes, come from the generator's existing name allocator. The
current user's filtered server description controls which samples and fields
can appear. A saved SDK can lag unrelated server additions. Each rendered sample
must still match its route, input and output layouts, and supplied field contracts.
Unsupported or stale samples show a short limitation instead of incomplete code.

Programs initialize the client with the API origin. Saved action paths include
the mounted root and selected `/vVERSION/` segment. Ordered sample path arguments
become the generated `SetPathParamInt` or `SetPathParamString` calls. Object/hash input uses
`NewInput().SelectParameters()` before setters; this preserves omitted fields,
explicit zero, false and empty strings. Nullable fields use `SetFIELDNil(true)`.
An empty request selects no fields. A missing request leaves input unallocated.

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
  description: saved_description,
  import_path: 'example.org/widget-sdk/v2/client',
  module_version: 'v2.3.4'
)
resolved = adapter.resolve(resource_path: %w[widget], action_name: 'update')
result = adapter.render(kind: :example, context: context, mode: :sync)
```

The context uses readers defined by the server's documentation context. The
adapter does not depend on the server gem. Results have either
`{status: :code, code: source}` or `{status: :limitation, reason: text}`. Renderers
return source/plain text; the server template escapes HTML once.

For SDK fixtures or an already captured schema, use the offline constructor. It preserves the ordinary URL constructor's generation options:

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

The harness saves a local schema fixture, generates its SDK, loads the matching
profile and writes the complete programs returned by the actual server renderer.
It formats, compiles and runs those programs against a disposable localhost
server. Cases include initialization, authentication methods, mounted/versioned
paths, nullable/false/zero/omitted inputs, list output, failures, global metadata
and action state. Go dependency and toolchain downloads are disabled. Generated
Go files remain disposable generator outputs.
