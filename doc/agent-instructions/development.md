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
  Quick/weekly CI blocks regressions, inconclusive timing and input/response
  errors. Keep exact source SHAs, matched dependency graphs and resolved locks
  with evidence; never update the fixed reference or budgets automatically.
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

See [the Rust client development guide](../../clients/rust/README.md) for the
locally resolved Ruby component bundle, pinned Rust formatter, generator unit
specs and separate runtime/integration checks. `make test-rust-unit` is the quick Ruby
check; `make test-rust` also compiles and exercises generated clients. The Rust
generator is included in the top-level release build and publishing workflow.
`make release-check` checks its shared version and dependency; `make release`
inspects the retained gem and runs the isolated packaged-generator smoke check.
`make test` includes the longer `test-rust` target. See
[Rust packaging](../../clients/rust/docs/releasing.md) for the standalone smoke
command and generated-client release checks.
