# Repository Guidelines

## Project Structure & Module Organization
- Core protocol docs live in `doc/`; reference implementations are in `servers/` (Ruby is current, Elixir is legacy) and `clients/` (Ruby, JS, Go, PHP, Elixir). Example APIs are under `examples/`.
- Ruby server library code sits in `servers/ruby/lib`, with specs in `servers/ruby/spec` and docs/templates under `servers/ruby/doc`.
- Client sources mirror their language: JS sources in `clients/js/src` build into `clients/js/dist`; Ruby/Go/PHP client libraries are under their respective folders with gem/composer metadata.
- `templates/` holds starter projects; `dist/` is for build artifacts; `utils/` contains helper scripts (e.g., doc sync).

## Build, Test, and Development Commands
- Each component has a `shell.nix` file. Use `nix-shell` to enter individual environments. From within the shell, standard language tools are used.
- The top-level directory also has a `shell.nix` file, which is used for tree-wide work, e.g. making new releases.
- Sync documentation into server packages with `make doc`.
- Run the full suite from repo root with `make test` (install deps first or use `nix-shell`; this starts local test servers and needs permission to bind localhost ports).
- Ruby server tests: from `servers/ruby`, run `bundle exec rspec` or `bundle exec rake spec`.
- JS client build: from `clients/js`, run `./node_modules/.bin/gulp` after installing deps to refresh `dist/haveapi-client.js`.
- PHP client tests: from `clients/php`, run `composer install` then `php vendor/bin/phpunit`; this boots a local Ruby test server from `servers/ruby/test_support/client_test_server.rb` and needs permission to bind a localhost port.

## Coding Style & Naming Conventions
- Ruby code follows the repo `.rubocop.yml` (2-space indent, relaxed metrics); run `bundle exec rubocop` in the relevant Ruby component before submitting.
- Keep generated outputs (`dist/`, `pkg/`, `html_doc/`) build-only—edit source files in `lib/`, `src/`, `doc/`, or templates instead.
- Tests follow RSpec `_spec.rb` naming. Module/class names should nest under `HaveAPI` and mirror directory structure.
- JS client code is plain ES5 bundled via gulp UMD; keep changes in `clients/js/src` and let the build regenerate `dist`.

## Testing Guidelines
- Prioritize coverage for protocol descriptions, authentication flows, validators, and parameter edge cases in `servers/ruby/spec`.
- Add regression specs alongside fixes; place shared helpers in `servers/ruby/spec/spec_helper.rb` or existing support dirs.
- For JS or other clients, add minimal repro scripts or harnesses near the component root if formal tests are absent, and document how to run them.

## Commit & Pull Request Guidelines
- Follow the project’s concise commit style: `area: change` (e.g., `servers/ruby: fix token auth`, `clients/js: rebuild dist`). Squash noise; keep each commit scoped.
- Overcommit git hooks must be passing, i.e. reported issues must be resolved.
- PRs should state purpose, affected components, and test evidence (`bundle exec rspec`, `gulp`, etc.). Link issues when relevant and note backward-compatibility or API surface changes.
- Avoid mixing version bumps with feature changes; use `make version` to update the shared `VERSION` value when coordinating releases.

## Branches
- `master` branch contains the latest development version.
- When a new major/minor release is made, a new brach is created, e.g. `haveapi-0.26`. Fixes from the master are than cherry-picked (`git cherry-pick -x`) into the release branch and a new patch version is made, e.g. `v0.26.1` in branch `haveapi-0.26`.
- Only the latest release branch is supported.

## Releasing a new version
- When releasing a new major/minor version, create a new release branch.
- When releasing a patch version, work within the release branch.
- `make version VERSION=<major>.<minor>.<patch>` will update versions of all components.
- Update `CHANGELOG.md` and add a brief description of changes for each component. If there are no changes to a component, it is not mentioned.
- Always run `make release` and `make publish` from within the top-level `nix-shell` so the correct toolchain is used; running them outside nix can produce build failures or mismatched Ruby versions.
- `make release` will build artifacts of all components. Run it inside `nix-shell`.
- `make publish` will upload the built artifacts to package repositories, e.g. rubygems.org, npmjs.com, etc. Run it inside `nix-shell` and always ask before publishing a new version.

## PHP client irregularity
- The PHP client at `clients/php/` must be released separately due to a restriction in `composer` -- it does not support monorepos, the PHP package is expected to live in the top-level directory.
- When releasing a new version, the contents of `clients/php/` is synchronized with another repository at `https://github.com/vpsfreecz/haveapi-client-php`.
- Synchronization is done by cloning repository `vpsfreecz/haveapi-client-php` and using rsyncto update/remove files.
- Release branches are not created in `vpsfreecz/haveapi-client-php`, since only the latest release is supported, only the `master` branch is updated.
- New version is tagged and the changes are pushed.
