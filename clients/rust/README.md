# Rust client generator

This Ruby generator turns a saved HaveAPI protocol 2 description into a typed,
self-contained Rust client for one explicit API version. The generated client
uses async reqwest by default and offers the same actions through the optional
`blocking` feature. Ruby and HaveAPI are generation tools, not dependencies of
the resulting Rust crate.

The client contract uses edition 2024, Rust 1.95 or newer, Serde, url 2.5,
and reqwest 0.13.5 with verified rustls TLS. Generation requires the exact
formatter version recorded in the client configuration. New test fixtures use
the formatter from the HaveAPI Nix shell; existing clients retain their own
recorded formatter. A separate acceptance check verifies Rust 1.95 because the
development compiler is newer.

## Development

From the HaveAPI root:

```sh
nix develop .#client-rust
cd clients/rust
bundle exec rspec spec/unit
bundle exec rubocop lib bin spec/unit spec/spec_helper.rb haveapi-rust-client.gemspec
```

The component shell installs the dependencies frozen in the tracked
`clients/rust/Gemfile.lock`. Use its Ruby interpreter with those gems; native
gems installed by this shell cannot be loaded by a different ambient Ruby.
The root Git hooks also need the root shell's dependencies: prepare them with
`nix develop --command true` before committing, then commit with the declared
Overcommit hooks enabled. Do not install gems concurrently in the same gem home.

`make test-rust-unit` runs the generator specs. `make test-rust` additionally
runs both runtime feature configurations and the generated-client protocol
harness. Compilation, linting Rust, server integration, MSRV and packaging can
take longer; use the development workspace's verification procedure when
working there. Unit specs never start a server or invoke Cargo.

## Generate a client

Keep acquisition separate from generation:

```sh
bundle exec haveapi-rust-client fetch https://api.example.test/v1.0/ \
  --api-version 1.0 --profile public --output schema/api-1.0.json
bundle exec haveapi-rust-client generate --schema schema/api-1.0.json \
  --api-version 1.0 --config generator.toml --output src/generated
bundle exec haveapi-rust-client generate --schema schema/api-1.0.json \
  --api-version 1.0 --config generator.toml --output src/generated --check
```

Run these commands from the consuming project with this generator available in
its Bundler environment. The explicit URL includes the selected version.
Neither command selects the server's default API version. Offline generation
uses only the saved schema, generator configuration, locked Ruby dependencies,
maintained runtime source and pinned formatter.

The handwritten crate entry point is:

```rust
mod generated;
pub use generated::*;
```

A generated action looks like
`api.vps().update(123).hostname("example").send().await?`. The blocking client
uses `blocking::Client` and ends the same chain in `.send()?`. Construct, use and
drop a blocking client outside an async runtime, or put its entire lifecycle
inside `tokio::task::spawn_blocking`. See the [runtime contract](runtime/README.md)
for authentication, errors, deadlines and blocking restrictions.

Read the [integration harness guide](spec/integration/README.md) for fixture
setup and acceptance commands.

Read [generation and snapshots](docs/generation.md) for configuration, naming,
metadata fidelity and ownership rules, and [packaging](docs/releasing.md) before
preparing a generator or generated-client release.

The [server documentation adapter](docs/documentation.md) provides optional
async and blocking examples for a configured published SDK profile.
