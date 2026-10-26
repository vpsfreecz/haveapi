# Rust client generator

Generate a typed Rust client for one explicit API version from a saved
[HaveAPI](https://github.com/vpsfreecz/haveapi) protocol 2 description. Generated
clients support async calls and an optional `blocking` feature. Their resource
names and routes are fixed; applications do not need Ruby or runtime discovery.

## Prepare the source tools and crate

From the HaveAPI checkout root:

```sh
nix develop .#client-rust
BUNDLE_GEMFILE="$PWD/clients/rust/Gemfile" bundle install
mkdir -p /path/to/widget-client/schema /path/to/widget-client/src
```

The component shell supplies Ruby 3.2 or newer, Rust and `rustfmt`, and prepares
an isolated Ruby bundle using the Ruby client from the same checkout. Retain the
checkout revision and resolved component lock with your generation inputs.

Create `/path/to/widget-client/Cargo.toml`:

```toml
[package]
name = "widget-client"
version = "0.1.0"
license = "MIT"
edition = "2024"
rust-version = "1.95"

[features]
default = []
blocking = ["reqwest/blocking"]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
url = "2.5"
reqwest = { version = "0.13.5", default-features = false, features = ["json", "rustls"] }

[dev-dependencies]
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
```

Record the selected formatter in `/path/to/widget-client/generator.toml`:

```sh
cat > /path/to/widget-client/generator.toml <<EOF
crate_name = "widget-client"
crate_version = "0.1.0"
license = "MIT"
edition = "2024"
rust_version = "1.95"
rustfmt_version = "$(rustfmt --version)"
EOF
```

Add the handwritten entry point `/path/to/widget-client/src/lib.rs`:

```rust
mod generated;
pub use generated::*;
```

The generator checks the existing crate manifest; it does not create or replace
it. See [crate configuration](docs/generation.md#configuration-and-crate-scaffold)
for formatter selection and dependencies. Building the TLS dependencies can
require a C toolchain.

## Fetch, save and generate

The example API at `https://example.test/v1.0/` has `Widget#Update` with path
`/v1.0/widgets/{widget_id}`, a nullable string `name` input, and `id` and `name`
outputs. Replace the example URL, version and resource names with those of your
API.

From the HaveAPI root in the prepared component environment:

```sh
BUNDLE_GEMFILE="$PWD/clients/rust/Gemfile" bundle exec ruby \
  clients/rust/bin/haveapi-rust-client fetch https://example.test/v1.0/ \
  --api-version 1.0 --profile public \
  --output /path/to/widget-client/schema/api.json
BUNDLE_GEMFILE="$PWD/clients/rust/Gemfile" bundle exec ruby \
  clients/rust/bin/haveapi-rust-client generate \
  --schema /path/to/widget-client/schema/api.json --api-version 1.0 \
  --config /path/to/widget-client/generator.toml \
  --output /path/to/widget-client/src/generated
BUNDLE_GEMFILE="$PWD/clients/rust/Gemfile" bundle exec ruby \
  clients/rust/bin/haveapi-rust-client generate \
  --schema /path/to/widget-client/schema/api.json --api-version 1.0 \
  --config /path/to/widget-client/generator.toml \
  --output /path/to/widget-client/src/generated --check
```

The schema's parent directory must exist. Fetch uses the exact mounted version
endpoint; it does not choose a server default. Generation uses local schema,
configuration, prepared dependencies, embedded runtime and the recorded formatter.
It makes no network request or dependency installation. `--check` reports stale
output without changing it. Keep handwritten files outside `src/generated`.

For Basic capture, set `WIDGET_PASSWORD` in your environment, then run:

```sh
BUNDLE_GEMFILE="$PWD/clients/rust/Gemfile" bundle exec ruby \
  clients/rust/bin/haveapi-rust-client fetch https://example.test/v1.0/ \
  --api-version 1.0 --profile basic-user --basic-user demo \
  --basic-password-env WIDGET_PASSWORD \
  --output /path/to/widget-client/schema/api.json
```

For an existing HaveAPI token, set `WIDGET_TOKEN` and run:

```sh
BUNDLE_GEMFILE="$PWD/clients/rust/Gemfile" bundle exec ruby \
  clients/rust/bin/haveapi-rust-client fetch https://example.test/v1.0/ \
  --api-version 1.0 --profile token-user --token-env WIDGET_TOKEN \
  --output /path/to/widget-client/schema/api.json
```

These authentication choices are mutually exclusive. Token capture uses anonymous
discovery at the same endpoint to select the advertised token header. Supply a
token you have already acquired. `--profile` labels the capture; it does not
change authentication. Permissions and enabled plugins determine which resources
the snapshot contains. Review saved defaults and
data before sharing it. Never retain credentials or tokens. Failed capture leaves
an existing output file intact.

## Use the generated client locally

In an application, refer to the crate you generated:

```toml
[dependencies]
widget-client = { path = "/path/to/widget-client" }
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
```

```rust
use widget_client::Client;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let api = Client::builder("https://example.test").build()?;
    let result = api.widget().update(1).name("new name".to_owned()).send().await?;
    println!("Name: {:?}", result.output.name);
    Ok(())
}
```

Give the builder the API root and mount prefix without `/v1.0`; generated routes
already contain the version. Protected actions can use `.basic_auth(user,
password)` or `.token(std::env::var("WIDGET_TOKEN")?)` before `.build()`, when
advertised by the API. Server permissions still apply.

For synchronous use, enable `features = ["blocking"]` on the same local crate,
import `widget_client::blocking::Client` and call `.send()?`. Construct, use and
drop a blocking client outside an async runtime; see the
[runtime contract](runtime/README.md#authentication-and-transport-policy).

Only fields you set are sent. Results contain typed `output`, metadata in `meta`
and `http_status`; optional outputs reflect fields hidden or omitted by the
server. Transport, HTTP/API and decoding failures return errors. See
[snapshots and generation](docs/generation.md) for ownership, recovery, naming,
null handling and source digests, and the [runtime reference](runtime/README.md)
for authentication and timeouts.

## Development and reference

- [Generator development](docs/development.md)
- [Integration harness](spec/integration/README.md)
- [Packaging and releases](docs/releasing.md)
- [Server documentation profiles](docs/documentation.md)
