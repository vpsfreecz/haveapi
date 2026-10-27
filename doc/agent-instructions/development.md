# Development commands

Required procedure selected by the repository AGENTS.md. The rules retain their
repository scope and precedence. Paths and commands below are relative to the
repository root unless explicitly stated otherwise.

## Build, Test, and Development Commands
- Use `nix develop` from the top-level directory for tree-wide work, e.g. making new releases.
- Component development shells are available as `nix develop .#server-ruby`,
  `nix develop .#client-ruby`, `nix develop .#client-js`,
  `nix develop .#client-go`, `nix develop .#client-python`,
  `nix develop .#client-rust`, and
  `nix develop .#example-ruby-activerecord-auth`. From within the shell,
  standard language tools are used.
- Sync documentation into server packages with `make doc`.
- Focused documentation checks: `make test-documentation` builds JavaScript
  declarations and runs renderer, profile, HTML and local asset checks.
  `make test-documentation-python` additionally checks renderer limits against
  the real Python request encoder, using the locked environment prepared by
  `make release-deps`. The full `make test` includes this supplemental check;
  standalone Ruby specs do not require the Python package environment.
- Opt-in documentation measurements: `make benchmark-documentation` in the
  prepared server Ruby shell emits JSON for context derivation and full HTML
  requests. Pass options through `BENCHMARK_DOCUMENTATION_ARGS`; see
  [the benchmark guide](../client-examples.md#documentation-benchmark) for shapes,
  optional Rust lanes and equivalent baseline/candidate runs. Fixture/mount setup
  is excluded from request measurements. Ordinary specs use deterministic
  ownership, traversal and allocation checks without wall-clock thresholds in
  ordinary specs.
- Required endpoint performance checks: see [performance testing](../performance.md)
  before changing fixtures, budgets or the performance workflow. `make
  test-performance` runs deterministic contracts; `make performance` and
  `make performance-compare` invoke the paired runner and replay classifier.
  Both profiles need the prepared Rust Ruby bundle for complete documentation
  pages. Quick/weekly batches target one/two seconds of baseline request work,
  with 20%/10% regression budgets and deterministic input/response validation.
  Response stability is checked within each verified revision; cross-revision
  body changes and byte deltas are diagnostic and never waive performance gates.
  Inconclusive timing stays diagnostic and is not a measured pass; do not retry
  automatically until it becomes green. Keep exact source SHAs, matched
  dependency graphs and resolved locks with evidence; never update the fixed
  reference or budgets automatically.
- Required current-client performance coverage: `make test-performance-clients`
  in the prepared unbundled benchmark shell checks every registered renderer and
  mode plus complete pages. This additional deterministic contract uses actual
  Go/Rust/TypeScript profiles; it does not change historical paired timing
  workloads or budgets. See [performance testing](../performance.md).
- Release tooling checks: `make release-check` and `make release-test` in the
  top-level Nix shell. `make release-deps` installs maintained-component
  dependencies and creates ignored local library locks. Prepare these inputs
  before versioning or running locked checks. `ruby utils/release/cli.rb
  check-clean` checks authored release metadata without requiring local locks;
  `check-inputs` validates prepared library inputs. See
  [Branches and releases](releases.md) for packaging and GitHub Actions
  publication.
- Run `make doc` before Ruby server specs. They check shared documentation and
  build/extract a real server gem to exercise the packaged documentation routes.
- Run the full suite from repo root with `make test` (install deps first or use `nix develop`; this starts local test servers and needs permission to bind localhost ports).
- Ruby server tests: from `servers/ruby`, run `bundle exec rspec` or `bundle exec rake spec`.
- JS client build: from `clients/js`, run `./node_modules/.bin/gulp` after installing deps to refresh `dist/haveapi-client.js`.
- PHP client tests: from `clients/php`, run `composer install` then `php vendor/bin/phpunit`; this boots a local Ruby test server from `servers/ruby/test_support/client_test_server.rb` and needs permission to bind a localhost port.
- Python checks: from `clients/python` in `.#client-python`, run
  `./utils/check.sh`. Use the shared `python utils/run_ruff.py` entrypoint through
  uv so Nix and CI use the same locked formatter. See
  [Python contributor guidance](../../clients/python/CONTRIBUTING.md).
- `nixpkgs` is updated weekly by the `update nixpkgs` GitHub workflow.
  For an on-demand update, prefer triggering that workflow manually. For a
  local update, set `CONFCTL_FLAKE` to the immutable package reference in
  `.github/workflows/update-nixpkgs.yml`, then run `./utils/update-nixpkgs.sh`
  and review its generated commit.
  The helper uses confctl's forward-only guard; a rejection or unavailable
  ancestry evidence stops the update. The workflow saves the original lock
  outside the checkout and checks the final lock again before its ordinary
  non-force push. If the target branch advances, rerun from its new baseline;
  do not rebase an old generated lock update. The commit subject must be
  `flake: nixpkgs <oldrev11> -> <newrev11>`.
  The workflow saves confctl's Git mirrors in `~/.cache/confctl` even when an
  update is rejected. Every update checks ancestry, whether the cache was
  restored or freshly cloned.
  See the [shared guard contract](https://github.com/vpsfreecz/confctl/blob/822c0e35dbe2549111912f539116b4225dfd3035/docs/flake-inputs.md#guarded-automated-updates) for supported sources and failure behavior.

## Rust generator and runtime

See [the Rust client development guide](../../clients/rust/docs/development.md)
for the locally resolved Ruby component bundle, pinned Rust formatter, generator
unit specs and separate runtime/integration checks. `make test-rust-unit` is the quick Ruby
check; `make test-rust` also compiles and exercises generated clients. The Rust
generator is included in the top-level release build and publishing workflow.
`make release-check` checks its shared version and dependency; `make release`
inspects the retained gem and runs the isolated packaged-generator smoke check.
`make test` includes the longer `test-rust` target. See
[Rust packaging](../../clients/rust/docs/releasing.md) for the standalone smoke
command and generated-client release checks.

## TypeScript generator

The generator lives in `clients/typescript`; see its
[user guide](../../clients/typescript/README.md) for CLI use and generated-client
examples. From the HaveAPI root:

```sh
nix develop
make test-typescript
bundle exec rubocop clients/typescript/lib clients/typescript/bin \
  clients/typescript/spec clients/typescript/haveapi-typescript-client.gemspec
```

The root shell prepares Ruby development dependencies and supplies Node. Prepare
the existing JavaScript component's dependencies before running the strict
emitted-source checks; they use TypeScript under `clients/js/node_modules`.
The fixtures compile with NodeNext/ES2022, `exactOptionalPropertyTypes`,
`noUncheckedIndexedAccess` and `verbatimModuleSyntax`. Unit checks need no live
API. Full-schema generation and server/consumer integration are separate checks.
This component shares `VERSION` and is included in release artifacts as
`haveapi-typescript-client`. The release build inspects both its retained gem and
the Ruby client's shared schema sources, then exercises the extracted generator
against the supported published JavaScript runtime. See
[release packaging](releases.md#build-only-checks-and-local-packaging).

`IR.build(snapshot)` returns deeply frozen symbol-key hashes and arrays.
`Emitter.new(ir, { runtime_import: 'haveapi-client' }).files` returns a sorted map
of relative paths to UTF-8 source with LF endings, without I/O. The generator alone
installs that map. Coordinate changes to this interface across parser and emitter.
Resource/action modules compose through internal factories; public entry points
re-export types explicitly without exposing those factories.

The writer replaces each file atomically and writes the ownership manifest last.
An interruption can leave a mixed tree. It compares recursive file hashes,
preserves timestamps for identical output and removes stale owned files and empty
directories. Keep the interrupted-generation recovery steps in the user guide
consistent with these guarantees.

### TypeScript snapshots and provenance

The format 1 JSON envelope has exactly `schema_format`, `api_version`,
`protocol_version`, `source_url`, `profile`, `mount_path` and `description` keys.
`schema_format` is `1`; `protocol_version` has major `2`. The source URL points to
the explicit version endpoint and must match `mount_path` and `api_version`.
The mount has leading and trailing `/`; a mounted API 7.0 fixture can use
`https://schema.invalid/v7.0/` with mount `/`. The description retains resources,
authentication discovery, metadata namespace and versioned help/routes.
Authentication resource operations remain validated provenance; the runtime owns
their API-root routes and they are excluded from generation. Manifest coverage
records application and authentication resource/action counts separately.

Capture code holding a structural description can use
`Snapshot.from_description(description:, api_version:, protocol_version:,
source_url:, profile:, mount_path: '/', diagnostics: [])` on
`HaveAPI::Schema::Snapshot`; Rust and TypeScript keep compatibility facades.
All three generators delegate their `fetch` subcommand to the shared
`HaveAPI::Schema::FetchCommand`. See the generator READMEs for component bundle
setup, public/Basic/token capture and explicit-version offline generation.
The helper removes structural prose, examples, validator messages and protected defaults, preserving
ordinary defaults, machine validators and real Custom/default/choice data keys.
Capture provenance and removal diagnostics belong in a separate file. Review
remaining data before sharing snapshots; never retain credentials, tokens or
database connection strings.

Capture and saved-snapshot validation check nested structural machine endpoints.
HTTP URLs cannot contain credentials, queries or fragments; paths cannot contain
traversal, queries or fragments. Help paths may use `?method=GET`, with `POST`,
`PUT`, `PATCH`, `DELETE` or `OPTIONS` also accepted as the method value. These
restrictions apply to description metadata, not parameter defaults, Custom JSON
or validator choice keys.

`Snapshot.canonical` recursively sorts object keys, preserves arrays, and writes
two-space UTF-8 JSON with LF endings and one terminal newline. The schema digest
covers those bytes. The manifest also records API/protocol versions, profile,
generator version/configuration, source digest and owned file hashes. Source
identity covers the executable, Ruby library, templates, Gemfile, gemspec and
Rakefile; it excludes checkout paths, timestamps, docs, tests and development
locks. It also binds `HaveAPI::Schema.source_identity`, which identifies the
loaded Ruby-client version and shared schema source under stable logical paths.
Offline source commands must explicitly select both `clients/ruby/lib` and
`clients/typescript/lib`, or use the prepared component bundle; the root tools
bundle alone does not provide generator dependencies. Pin the exact HaveAPI
revision and retain tool/dependency versions in downstream provenance.

The shared schema API is unreleased source functionality. A matching gem version
range does not prove that an older installed Ruby client has this API; generators
fail clearly when the required capability is missing. Use the component Gemfile
with its explicit sibling Ruby-client path when working from source. Rust and
TypeScript facades preserve their native error classes. Rust snapshot loading now
also validates contextual nested machine endpoints, matching TypeScript capture
and load; unsafe saved endpoints that older Rust loading accepted are rejected.
