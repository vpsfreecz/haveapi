# Rust client generator

This Ruby generator turns a saved HaveAPI protocol 2 description into a typed,
self-contained Rust client for one explicit API version. Generated clients
support async calls and the same actions through an optional `blocking` feature.
Ruby and HaveAPI are needed to generate the crate; applications using it need
only its Rust dependencies.

The [generated vpsAdmin Rust client](https://github.com/vpsfreecz/vpsadmin-rust-client)
is ready to use with vpsAdmin. You can [install the generated crate](#use-the-generated-client)
directly.

## Install the generator

The generator requires Ruby 3.2 or newer:

```sh
gem install haveapi-rust-client
```

Generated crates use edition 2024 and require Rust 1.95 or newer. Their runtime
uses Serde, url 2.5 and reqwest 0.13.5 with rustls TLS. Building the TLS
dependencies may require a C toolchain. Generation also requires the exact
`rustfmt` version recorded in the client configuration; see
[configuration and crate setup](docs/generation.md#configuration-and-crate-scaffold)
for the dependencies, Cargo features and formatter selection.

## Generate a client

Create a Rust library crate with `Cargo.toml` and `generator.toml` matching the
[configuration and crate setup](docs/generation.md#configuration-and-crate-scaffold).
The generator checks an existing crate manifest but does not create it. Run the
following commands from that crate's root to save a description, generate the
client and check that it is current. Replace `CHOSEN_API_VERSION` with the
numeric API version you want to generate:

```sh
api_version='CHOSEN_API_VERSION'
mkdir -p schema
haveapi-rust-client fetch "https://api.vpsfree.cz/v${api_version}/" \
  --api-version "$api_version" --profile public --output schema/api.json
haveapi-rust-client generate --schema schema/api.json \
  --api-version "$api_version" --config generator.toml --output src/generated
haveapi-rust-client generate --schema schema/api.json \
  --api-version "$api_version" --config generator.toml --output src/generated --check
```

The fetch URL and `--api-version` select the same explicit version. The snapshot
contains only the API surface visible to its capture profile. Generation is
offline and uses the saved schema, configuration, prepared Ruby dependencies,
embedded runtime source and pinned formatter. `--check` reports stale output
without changing it. Generated clients have fixed routes and perform no runtime
discovery or API version selection.

Add this handwritten entry point in `src/lib.rs`, outside the managed generated
directory:

```rust
mod generated;
pub use generated::*;
```

Read [generation and snapshots](docs/generation.md) for naming, metadata,
snapshot provenance and generated-file ownership rules.

## Use the generated client

These examples use the generated vpsAdmin crate. For another API, use its
generated crate and resource/action names. Give the client the server root,
including any mount path, without the generated API version suffix.

### Async

Add the client and Tokio to your application's `Cargo.toml`:

```toml
[dependencies]
vpsadmin-client = "0.1"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
```

Public actions work without authentication:

```rust
use vpsadmin_client::Client;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let api = Client::builder("https://api.vpsfree.cz").build()?;
    let stats = api.cluster().public_stats().send().await?.output;
    println!("VPS count: {:?}", stats.vps_count);
    Ok(())
}
```

### Blocking

Enable the generated crate's `blocking` feature:

```toml
[dependencies]
vpsadmin-client = { version = "0.1", features = ["blocking"] }
```

Import the blocking client and call `.send()?`:

```rust
use vpsadmin_client::blocking::Client;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let api = Client::builder("https://api.vpsfree.cz").build()?;
    let stats = api.cluster().public_stats().send()?.output;
    println!("VPS count: {:?}", stats.vps_count);
    Ok(())
}
```

Construct, use and drop a blocking client outside an async runtime. Async
applications should use the async client or put the entire blocking-client
lifecycle inside `tokio::task::spawn_blocking`. See the
[runtime contract](runtime/README.md#authentication-and-transport-policy) for
deadlines and blocking-task cancellation limits.

### Authentication, actions and results

For an existing HaveAPI token, configure the builder before calling `.build()`:

```rust
let api = Client::builder("https://api.vpsfree.cz")
    .token(std::env::var("VPSADMIN_TOKEN")?)
    .build()?;
```

The builder also supports `.basic_auth(username, password)` and
`.oauth2_token(token)`. Choose one method supported by the generated API.
Token acquisition and renewal are explicit actions; they do not run automatically.

Resource methods return action builders. Pass resource IDs to actions such as
`api.vps().show(123)`, set input fields on the builder, then call `.send().await?`
or `.send()?`. Only fields you set are sent. Responses contain typed `output`,
action metadata in `meta` and `http_status`. Output fields use `Option` because
permissions and partial responses can omit them.

The examples propagate errors with `?`; transport failures, unsuccessful HTTP
or API responses and invalid response data return errors. See the
[runtime contract](runtime/README.md) for input/null handling, partial
associations, authentication, timeouts and error diagnostics, and the
[vpsAdmin API reference](https://docs.rs/vpsadmin-client) for concrete actions
and types.

## Development and reference

- [Generator development](docs/development.md): Nix setup, Ruby dependencies and quick checks.
- [Integration harness](spec/integration/README.md): fixtures and acceptance commands.
- [Packaging and releases](docs/releasing.md): generator and generated-client release checks.

The [server documentation adapter](docs/documentation.md) provides optional
async and blocking examples for a configured published SDK profile.
