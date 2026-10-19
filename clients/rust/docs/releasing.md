# Packaging the Rust generator and generated clients

The Ruby gem is `haveapi-rust-client` and follows HaveAPI's shared VERSION.
`make version` updates its version alongside existing components. The generator
is currently an explicit packaging target; the existing broad HaveAPI release
and publication workflow does not build or publish it.

Prepare its package from `clients/rust` in the component Nix shell:

```sh
bundle exec rake build
```

The gem includes Ruby/ERB sources, the Ruby dependency lock and maintained runtime
source. It excludes the private Cargo harness and integration fixtures. Inspect
the built package and test generation from it before a release. Publishing a new
gem version requires separate authorization and an explicit publication workflow;
`make publish` does not publish this gem.

Generated Rust crates have their own SemVer and Cargo.lock. Their API-version
constant and schema digest identify the target independently of the crate
version. Adding required input, changing public types or removing actions can
require a breaking crate release; increasing the MSRV is a deliberate release
decision. Extra response fields and unknown choice values remain compatible
through optional fields and open string values.

Before shipping a generated client, verify deterministic offline regeneration
and read-only `--check`, formatting, async and blocking library/examples, protocol
fixtures, the declared minimum Rust version and `cargo package`. Inspect the
archive for copied runtime source and ordinary registry dependencies. No Ruby,
HaveAPI checkout or private runtime crate should be needed to build it.

A runtime source fix reaches consumers only after regeneration and release of
each affected generated crate. Keep the prior schema, generator revision,
lockfiles and generated revision available for recovery. Pinning a previous
crate version can restore software behavior but cannot reverse server changes
made by an API action.
