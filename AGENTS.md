# Repository Guidelines

## Project Structure & Module Organization
- Core protocol docs live in `doc/`; reference implementations are in `servers/` (Ruby is current, Elixir is legacy) and `clients/` (Ruby, JS, Go, PHP, Elixir). Example APIs are under `examples/`.
- Ruby server library code sits in `servers/ruby/lib`, with specs in `servers/ruby/spec` and docs/templates under `servers/ruby/doc`.
- Client sources mirror their language: JS sources in `clients/js/src` build into `clients/js/dist`; Ruby/Go/PHP client libraries are under their respective folders with gem/composer metadata.
- `templates/` holds starter projects; `dist/` is for build artifacts; `utils/` contains helper scripts (e.g., doc sync).

## Build, Test, and Development Commands
- Use `nix develop` from the top-level directory for tree-wide work, e.g. making new releases.
- Component development shells are available as `nix develop .#server-ruby`,
  `nix develop .#client-ruby`, `nix develop .#client-js`,
  `nix develop .#client-go`, and
  `nix develop .#example-ruby-activerecord-auth`. From within the shell,
  standard language tools are used.
- Sync documentation into server packages with `make doc`.
- Run `make release-check` and `make release-test` for release metadata and
  helper checks. `make release-deps` installs maintained-component dependencies.
- Run `make doc` before Ruby server specs. They check shared documentation and
  build/extract a real server gem to exercise the packaged documentation routes.
- Run the full suite from repo root with `make test` (install deps first or use `nix develop`; this starts local test servers and needs permission to bind localhost ports).
- Ruby server tests: from `servers/ruby`, run `bundle exec rspec` or `bundle exec rake spec`.
- JS client build: from `clients/js`, run `./node_modules/.bin/gulp` after installing deps to refresh `dist/haveapi-client.js`.
- PHP client tests: from `clients/php`, run `composer install` then `php vendor/bin/phpunit`; this boots a local Ruby test server from `servers/ruby/test_support/client_test_server.rb` and needs permission to bind a localhost port.
- `nixpkgs` is updated weekly by the `update nixpkgs` GitHub workflow.
  For an on-demand update, prefer triggering that workflow manually. For a
  local update, run `./utils/update-nixpkgs.sh`, review the generated commit,
  and push it. The commit subject must be
  `flake: nixpkgs <oldrev11> -> <newrev11>`.

## Coding Style & Naming Conventions
- Ruby code follows the repo `.rubocop.yml` (2-space indent, relaxed metrics); run `bundle exec rubocop` in the relevant Ruby component before submitting.
- Keep generated outputs (`dist/`, `pkg/`, `html_doc/`) build-only—edit source files in `lib/`, `src/`, `doc/`, or templates instead.
- Tests follow RSpec `_spec.rb` naming. Module/class names should nest under `HaveAPI` and mirror directory structure.
- JS client code is plain ES5 bundled via gulp UMD; keep changes in `clients/js/src` and let the build regenerate `dist`.

## Localization
- Edit HaveAPI framework and client translations only in `i18n/haveapi.yml`.
- Run `bundle exec rake i18n:update` after translation changes. This regenerates
  server Ruby locale files and package-local client catalogs for Ruby, PHP, JS,
  and Go clients.
- Do not edit generated locale/catalog artifacts directly. They contain a
  generated-file header and will be overwritten by `i18n:update`.
- Applications can localize action parameter labels/descriptions and
  `choices`/`include` labels by setting the server `parameter_i18n_scope` to
  the application root. HaveAPI looks up exact resource/action keys, then
  shared resource input/output keys, resource attributes, and shared
  `attributes.<name>` keys. Use `label_key`/`desc_key` only for explicit
  overrides.

## Testing Guidelines
- Prioritize coverage for protocol descriptions, authentication flows, validators, and parameter edge cases in `servers/ruby/spec`.
- Add regression specs alongside fixes; place shared helpers in `servers/ruby/spec/spec_helper.rb` or existing support dirs.
- For JS or other clients, add minimal repro scripts or harnesses near the component root if formal tests are absent, and document how to run them.

## Commit & Pull Request Guidelines
- Follow the project’s concise commit style: `area: change` (e.g.,
  `servers/ruby: fix token auth`, `clients/js: rebuild dist`). Squash noise;
  keep each commit scoped.
- Commit messages must say what is changing and why. Describe the problem in
  the body and summarize the solution.
- Wrap commit message subject and body lines at 80 characters.
- Overcommit git hooks must be passing, i.e. reported issues must be resolved.
  Do not bypass hooks with `--no-verify`, `SKIP=...`, `LEFTHOOK=0`, or similar.
- Write commit messages through a temporary file and commit with
  `git commit -F`.
- PRs should state purpose, affected components, and test evidence
  (`bundle exec rspec`, `gulp`, etc.). Link issues when relevant and note
  backward-compatibility or API surface changes.
- Avoid mixing version bumps with feature changes; use `make version` to update
  the shared `VERSION` value when coordinating releases.

## Branches and releases

Before selecting a release/backport branch, changing versions, publishing or
synchronizing the PHP client, read [Branches and releases](doc/agent-instructions/releases.md)
in full. It defines the supported release line, maintained packages, GitHub
Actions publication, setup and recovery.

Always ask before publishing a new version. Run release commands in the top-level
Nix shell. GitHub Actions publishes retained artifacts after approval in the
protected `release` environment. Build-only runs do not publish. Elixir components
are unmaintained and excluded from releases.
