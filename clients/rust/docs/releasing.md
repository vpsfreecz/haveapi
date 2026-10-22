# Packaging the Rust generator and generated clients

The Ruby gem is `haveapi-rust-client` and follows HaveAPI's shared VERSION.
`make version` updates its version, client dependency and tracked generator lock
alongside existing components. The top-level release build includes this gem,
and the protected publishing job uploads it after `haveapi-client`. Configure
its RubyGems publisher before release; a new gem can use a pending publisher
without a manual seed upload. Follow the
[shared release procedure](../../../doc/agent-instructions/releases.md) for
registry setup, approval, retained artifacts and recovery.

Prepare its package from `clients/rust` in the component Nix shell:

```sh
bundle exec rake build
```

The gem includes Ruby/ERB sources, the executable, documentation, Ruby dependency
lock and maintained runtime source. It excludes the private Cargo harness and
integration fixtures. The top-level `make release` builds and inspects this gem,
retains its checksum and source in the shared manifest, and runs an isolated
installed-package generation check. To repeat that check against retained
artifacts in the root Nix shell:

```sh
ruby utils/release/rust_smoke.rb dist
```

The check loads the generator from the package and verifies its copied runtime.
Run the broader generator, runtime and generated-client checks as well.
`make test-rust-unit` runs the quick generator specs; `make test-rust` covers
those specs, both runtime feature configurations
and generated-client protocol acceptance. Top-level `make test` includes that
Rust target. Publishing a new gem version requires separate authorization and
approval in the protected release environment; `make publish` exits without
publishing.

Generated Rust crates have their own SemVer and Cargo.lock. Their API-version
constant and schema digest identify the target independently of the crate
version. Adding required input, changing public types or removing actions can
require a breaking crate release; increasing the MSRV is a deliberate release
decision. Extra response fields and unknown choice values remain compatible
through optional fields and open string values.

The embedded runtime has no separate registry release. Its `haveapi-runtime-tests`
Cargo package is a private development harness with `publish = false`, not an
artifact of HaveAPI's shared version. No crates.io token is needed to release
the generator gem. Publish a generated crate through its consuming project's
own release procedure and registry identity.

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
