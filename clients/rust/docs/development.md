# Rust generator development

From the HaveAPI root:

```sh
nix develop .#client-rust
cd clients/rust
bundle exec rspec spec/unit
bundle exec rubocop lib bin spec/unit spec/spec_helper.rb haveapi-rust-client.gemspec
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
`make test-rust` additionally runs both runtime feature configurations and the
generated-client protocol harness. Unit specs never start a server or invoke
Cargo. Compilation, Rust linting, server integration, MSRV and packaging checks
can take longer; follow the development workspace's verification procedure when
working there.

The Nix shell supplies the development compiler and formatter. New test
fixtures record that formatter; existing clients retain their own exact
configured formatter. A separate acceptance check verifies Rust 1.95 because
the development compiler is newer. See
[generation configuration](generation.md#configuration-and-crate-scaffold), the
[runtime checks](../runtime/README.md#development-checks), the
[integration harness](../spec/integration/README.md) and
[packaging](releasing.md) for the corresponding commands and input requirements.
