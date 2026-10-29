# Rust generator development

From the HaveAPI root:

```sh
nix develop .#client-rust
cd clients/rust
bundle exec rspec spec/unit
```

Run Ruby style checks from the HaveAPI root in the default Nix shell, using the
root bundle:

```sh
BUNDLE_GEMFILE="$PWD/Gemfile" bundle exec rubocop clients/rust/lib clients/rust/bin \
  clients/rust/spec clients/rust/haveapi-rust-client.gemspec
```

The component shell runs `bundle install` for this library's dependency ranges
and creates an ignored local `clients/rust/Gemfile.lock`. Keep that prepared
resolution unchanged while building and checking a candidate, and retain the
lock with its build evidence. Fresh resolutions can select different compatible
dependencies; the source commit alone does not fix the Ruby dependency graph.
Use the shell's Ruby interpreter with those gems; native gems installed by this
shell cannot be loaded by a different ambient Ruby.

The root Git hooks also need the root shell's dependencies: prepare them with
`nix develop --command true` before committing, then commit with the declared
Overcommit hooks enabled. Do not install gems concurrently in the same gem home.

From the HaveAPI root, `make test-rust-unit` runs the generator specs.
The specs check generated Rust with the recorded formatter, including failures
after a successful version probe, without starting Cargo or a server. They also
verify that every copied runtime file retains its maintained source bytes.
`make check-rust` runs the runtime's read-only `cargo fmt` check.
`make test-rust` additionally checks formatting and runs both runtime feature
configurations, the prepared server fixture contracts and the generated-client
protocol harness.
Quick unit specs need only the Rust component bundle; they never load the server
application, start a listener or invoke Cargo. Compilation, Rust linting, server
integration, MSRV and packaging checks can take longer; follow the development
workspace's verification procedure when working there.

The generated-client harness also runs `cargo fmt --check` over its complete
temporary crate, including the copied acceptance tests. This check precedes its
compilation and protocol tests. Clippy remains a separate runtime lint check.

The Nix shell supplies the development compiler and formatter. New test
fixtures record that formatter; existing clients retain their own exact
configured formatter. A separate acceptance check verifies Rust 1.95 because
the development compiler is newer. See
[generation configuration](generation.md#configuration-and-crate-scaffold), the
[runtime checks](../runtime/README.md#development-checks), the
[integration harness](../spec/integration/README.md) and
[packaging](releasing.md) for the corresponding commands and input requirements.
