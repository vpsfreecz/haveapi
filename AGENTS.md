# Repository Guidelines


## Required procedures

Before each activity below, read every applicable procedure in full. These are
required instructions with repository scope, including outside this workspace.
Resolve table links from this AGENTS.md, not the shell directory. Recheck routes
when scope changes; pass applicable paths to authorized subagents before they
act. Reuse unchanged procedures already read in the current context; otherwise
reread them. Summaries do not replace reading. If a required file is unreadable,
stop the affected action and report it.

| Before this activity | Read |
| --- | --- |
| Selecting/running builds, tests or documentation generation; changing Nix inputs | [Development commands](doc/agent-instructions/development.md) |
| Changing framework/client translations, generated catalogs, parameter metadata or localization lookup behavior | [Localization](doc/agent-instructions/localization.md) |
| Selecting a branch for a release/backport, versioning, publishing or synchronizing the PHP client | [Branches and releases](doc/agent-instructions/releases.md) |

Always ask before publishing a new version. Do not edit generated locale or
catalog artifacts directly; translation changes start in `i18n/haveapi.yml` and
require the localization procedure. Release and publish commands must run in the
top-level Nix development shell.


## Project Structure & Module Organization
- Core protocol docs live in `doc/`; reference implementations are in `servers/` (Ruby is current, Elixir is legacy) and `clients/` (Ruby, JS, Go, PHP, Elixir). Example APIs are under `examples/`.
- Ruby server library code sits in `servers/ruby/lib`, with specs in `servers/ruby/spec` and docs/templates under `servers/ruby/doc`.
- Client sources mirror their language: JS sources in `clients/js/src` build into `clients/js/dist`; Ruby/Go/PHP client libraries are under their respective folders with gem/composer metadata.
- `templates/` holds starter projects; `dist/` is for build artifacts; `utils/` contains helper scripts (e.g., doc sync).

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
