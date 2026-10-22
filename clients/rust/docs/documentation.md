# Rust examples in server documentation

The optional `HaveAPI::RustClient::Documentation` adapter maps a published Rust
SDK's saved snapshot and TOML configuration to server documentation. It uses the same
Snapshot validation, complete IR, naming scopes and types as the generator.
Construction and rendering make no network requests and run no generator, compiler
or formatter. The server loads its trusted local files at startup.

An API operator installs the matching `haveapi-rust-client` gem and configures a
profile before mounting the server:

```ruby
api.documentation_clients(
  '1.0',
  rust: {
    snapshot_path: '/srv/api/sdk/schema/api-1.0.json',
    generator_config_path: '/srv/api/sdk/generator.toml',
    generator_version: HaveAPI::RustClient::VERSION
  }
)
```

Use the exact generator version that produced the published SDK. The profile's
package name and package version come from `crate_name` and `crate_version` in
that SDK's existing [generator config](generation.md). They are independent of
the API and HaveAPI package versions. Rust imports normalize crate-name hyphens
to underscores. Configure a profile only for an SDK that users can install; the
examples do not publish or generate that package.

The server hides both Rust variants when that API version has no Rust profile.
Invalid configured profiles fail at startup. A configured profile can still serve examples after unrelated additions to the
live API. Each rendered sample must match the saved route,
HTTP method, input and output layouts, and the contracts of the parameters it
uses. The adapter
checks the full SDK map against the current user's filtered help and sample;
it never recomputes names from a reduced schema or prints hidden saved defaults.
An unavailable action, changed parameter or unsupported value produces a short
limitation in place of code. Filesystem paths remain outside rendered output.

Both variants show a complete program and Cargo dependency comments. Async
programs use Tokio and `.send().await?`. Blocking programs enable the SDK's
`blocking` feature and construct, use and drop the client in a synchronous
`main`, outside async runtime threads. `HAVEAPI_BASE_URL` can override the shown
mounted root. Authenticated actions use advertised existing credentials from
`HAVEAPI_USER`/`HAVEAPI_PASSWORD` or `HAVEAPI_TOKEN`; authentication examples never
invent an OAuth acquisition flow or automatically follow token challenges.

Object setters preserve null, zero, false and empty strings, and leave omitted
fields unset.
Lists use generated `Input` structs with `InputValue` fields and
`..Default::default()` for omitted values. GET lists and nested Custom query
values produce limitations. The example DSL has no metadata input channel, so actions requiring metadata
show a limitation. Responses expose
`output`, typed `meta` and `http_status`. Fields accessed in examples must occur
in the authorized sample. Rust provides explicit action-state calls rather
than an automatic operation-wait helper. Request success and timeouts do not
establish whether a server-side operation finished or was rolled back.

## Verification

The pure adapter specs and server renderer bridge specs run before compilation:

```sh
nix develop .#client-rust --command bash -c \
  'cd clients/rust && bundle exec rspec spec/unit/documentation_spec.rb spec/unit/documentation_harness_spec.rb'
nix develop .#server-ruby --command bash -c \
  'cd servers/ruby && bundle exec rspec spec/client_examples/rust_client_spec.rb'
```

The acceptance runner extracts actual `RustAsyncClient.render` and
`RustBlockingClient.render` source. It generates a matching temporary fixture
SDK, compiles the emitted imports, paths, methods and types, and executes the
programs against the existing disposable HaveAPI fixture at `/` and
`/mounted/api/`. It adds output assertions without replacing emitted requests.
Authentication checks compose the emitted authentication builder with the
emitted action body. It tests both modes with the development compiler and
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
