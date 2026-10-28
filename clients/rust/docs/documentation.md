# Rust examples in server documentation

The optional `HaveAPI::RustClient::Documentation` adapter uses the generator's
Snapshot validation, IR and naming rules to map a configured SDK to server
examples. It makes no network requests and runs no generator, compiler or
formatter during construction or rendering. Install `haveapi-rust-client`
alongside the server, then register a profile before mounting:

```ruby
api.documentation_clients('1.0', rust: { crate_name: 'widget-client' })
api.mount('/api/')
```

`generator_version` defaults to the server's `HaveAPI::VERSION` and must match
the installed generator gem. An explicit value requires the installed generator
to report that version; it never downloads one. The SDK's version and API version
are independent of that generator version. Imports replace crate-name hyphens
with underscores and use the generator's reserved-name rules.

`crate_version` is optional. When omitted or nil, registry examples show
`cargo add widget-client` (or `cargo add widget-client --features blocking`).
Cargo chooses a compatible release according to its resolver, manifest,
toolchain and existing lockfile. The server does not resolve it and never emits
`version = "latest"`. To control version selection, supply a version such as
`crate_version: '1.2.3'`. Its Cargo version-requirement semantics remain intact;
it does not silently become an exact `=` constraint. Separate Tokio/serde_json
requirements are still shown.

Unpublished SDKs can use an explicit Git source instead of a registry release:

```ruby
api.documentation_clients('7.0',
  rust: {
    crate_name: 'vpsadmin-client',
    source: {
      git: 'https://github.com/vpsfreecz/vpsadmin-rust-client',
      rev: 'ff876abe17e3301da62c1b6afbda055ec89db9d2'
    }
  }
)
```

The emitted Cargo dependency contains that `git` and full `rev`; an explicitly
supplied crate version additionally constrains the source package. Blocking
examples add `features = ["blocking"]`. Only absolute HTTPS URLs without
credentials/query/fragment/control characters and 40-hex revisions are accepted.
Branches, tags, paths and custom registries are rejected. The server never
fetches this repository or publishes the crate. Configuring its name or source
does not establish that the SDK matches an API surface.

At the end of mount, the server builds the adapter from the complete selected
API version, including authentication routes and changes from post-mount hooks.
The private structural copy excludes examples, prose and parameter defaults,
while retaining canonical sibling names, ancestor paths and types. Requests use
their own authorized help. Automatic mode assumes that the SDK matches the
current generation contract; its package name or version alone cannot prove
that. An older SDK can lack actions or use different names after additions or
route changes.

For an older or subset SDK, use the optional
`snapshot_path: '/srv/api/sdk/schema/api-1.0.json'` with inline crate identity.
The legacy `generator_config_path: '/srv/api/sdk/generator.toml'` is also retained
as an alternative to inline `crate_name`/`crate_version`. It validates the full
existing [generator configuration](generation.md) and may use either automatic
schema or a saved snapshot. Do not mix the two identity forms. Saved file paths
must be trusted absolute local paths; files are loaded during registration.
Inline documentation does not need license, formatter or compiler packaging
settings. An older pinned generator can use a suitable legacy file profile;
automatic/inline mode requires the new factory interface and rejects missing
support at startup.

The server hides both Rust variants when no profile exists for that API version.
Invalid profiles and actual generator-version mismatches fail startup. Adapter
initialization occurs only once per mount and publishes no partial profiles on
failure. Request-local authorized descriptions still control visible actions,
fields and samples, including across users and locales. For saved models, each
sample must match its route, method, layouts and supplied parameter contracts.
Unavailable or stale samples produce a limitation. Private schema, hidden
defaults, local paths and initialization diagnostics never enter rendered output.
See the [server profile guide](../../../doc/client-examples.md) for compatibility
and rollback requirements.

The adapter selects the action or advertised authentication provider from the
current authorized description before normalizing that subtree. The private
saved model resolves SDK names; it cannot establish authorization. Authentication
still compares the complete supplied provider description with authorized help,
and action rendering validates live routes and supplied parameter contracts.
Symbol/string keys retain last-insertion collision behavior. No authorized
description or rendering decision is cached across contexts or users.

Normalization avoids unrelated resource descendants. Ancestor map lookup and
saved-model action resolution can still depend on sibling/action counts. This
does not make the complete render operation constant-time. Server context
derivation shares unchanged owned data, while explicitly supplied resources,
actions and samples still cross its copying boundary.

The pure in-memory factories use the same resolve/render interface as legacy
`Documentation.new(snapshot:, config:)`:

```ruby
adapter = HaveAPI::RustClient::Documentation.from_description(
  description: full_description, api_version: '1.0',
  protocol_version: HaveAPI::PROTOCOL_VERSION, mount_path: '/api/',
  crate_name: 'widget-client', crate_version: nil, source: nil
)
# Or use Documentation.from_snapshot(snapshot:, crate_name:, crate_version: nil, source: nil).
```

Their internal structural URL is not an SDK provenance source or emitted request
URL. Requests use the real server context. Actual SDK generation still requires
its full versioned packaging configuration; these factories do not relax it.

Simple action examples assume that initialization and authentication have
established `api`. They show the actual call and sample output. Async fragments
belong in an async function returning `Result<(), Box<dyn std::error::Error>>`;
blocking fragments use a synchronous function with that return type, outside
async runtime threads. The `?` operator propagates request and conversion errors.
Both detail levels share sample validation and limitations.

**With error handling** shows a complete program and Cargo dependency comments.
Async programs use Tokio and `.send().await?`. Blocking programs enable the SDK's
`blocking` feature and construct, use and drop the client in a synchronous
`main`, outside async runtime threads. `HAVEAPI_BASE_URL` can override the shown
mounted root. Authenticated actions use advertised existing credentials from
`HAVEAPI_USER`/`HAVEAPI_PASSWORD` or `HAVEAPI_TOKEN`; authentication examples never
invent an OAuth acquisition flow or automatically follow token challenges.

Object setters preserve null, zero, false and empty strings, and leave omitted
fields unset. Lists use generated `Input` structs with `InputValue` fields and
`..Default::default()` for omitted values. GET lists and nested Custom query
values produce limitations. The example DSL has no metadata input channel, so
actions requiring metadata show a limitation. Responses expose `output`, typed
`meta` and `http_status`. Fields accessed in examples must occur
in the authorized sample. Rust provides explicit action-state calls rather
than an automatic operation-wait helper. Request success and timeouts do not
establish whether a server-side operation finished or was rolled back.

## Verification

The pure adapter specs and server renderer bridge specs run before compilation:

```sh
nix develop .#client-rust --command bash -c \
  'cd clients/rust && bundle exec rspec spec/unit/documentation_spec.rb spec/unit/documentation_performance_spec.rb spec/unit/documentation_harness_spec.rb'
nix develop .#server-ruby --command bash -c \
  'cd servers/ruby && bundle exec rspec spec/client_examples/rust_client_spec.rb'
```

The performance unit specs count normalization work around real renders and
check output/authorization parity as unrelated resource trees grow. They use no
wall-clock budget. The opt-in [documentation benchmark](../../../doc/client-examples.md#documentation-benchmark)
adds timing and allocation evidence. With server and Rust generator Ruby
dependencies prepared, pass `--rust` through `BENCHMARK_DOCUMENTATION_ARGS` to
include a matching profile in HTML and measure async/blocking adapter action and
authentication rendering separately. These lanes do not generate or compile an
SDK. Compare the same fixture, runtime, dependency inputs and output digests
against both implementation revisions before claiming a measured improvement.

The context must expose `detail` as `:simple` or `:thorough`. The acceptance runner
extracts actual `RustAsyncClient.render` and `RustBlockingClient.render` source.
It generates a matching temporary fixture
SDK, compiles the emitted imports, paths, methods and types, and executes the
programs for both detail levels against the existing disposable HaveAPI fixture
at `/` and `/mounted/api/`. It adds output assertions without replacing emitted
requests. Simple fragments use separately rendered setup. Authentication checks
compose the emitted authentication builder with the emitted action body.
It tests both modes with the development compiler and
Rust 1.95, including zero/false/empty/null/omitted inputs, nested Custom, lists,
nested resources, failure branches, metadata, existing credentials and an
action-state reference. The fixture uses local test credentials and in-memory
data.

Prepare the Rust/server environments as described in the
[integration guide](../spec/integration/README.md). Supply absolute paths to
the independently selected Rust 1.95 Cargo and compiler executables:

```sh
HAVEAPI_RUST_DOCUMENTATION=1 \
HAVEAPI_RUST_MSRV_CARGO=/path/to/rust-1.95/bin/cargo \
HAVEAPI_RUST_MSRV_RUSTC=/path/to/rust-1.95/bin/rustc \
HAVEAPI_RUST_DOCUMENTATION_EVIDENCE=/path/to/new-evidence-directory \
nix develop .#client-rust --command ruby clients/rust/spec/documentation/run.rb
```

The optional `HAVEAPI_RUST_DOCUMENTATION_EVIDENCE` directory retains separate
`root` and `mounted-api` receipts: snapshot, generator TOML, Cargo manifest and
lockfile, generated source and ownership manifest, emitted programs and selected
tool paths/versions. Choose a fresh directory; existing mount receipts cause an
error. Build outputs and caches remain temporary. A failed run retains whichever
fixture artifacts were available before the failure.

Ordinary unit specs do not start this runner. Temporary generated SDK/source,
Cargo outputs and the owned server are removed by their native runner cleanup;
failed server startup retains the integration launcher's private diagnostic log.
