# Branches and releases

Required procedure selected by AGENTS.md. Paths and commands are relative to the
repository root. Always ask before publishing a new version. Preparing release
metadata or running a build does not authorize publication.

## Branches and packages

`master` records the latest major/minor line as `X.Y.0`, with synchronized
component versions and internal dependency constraints. Prepare and integrate
each major/minor bump on master before cutting `haveapi-X.Y` from it. Master
integration requires its own authorization; preparing a release does not grant it.

For a patch release, work on the release branch and backport fixes with
`git cherry-pick -x`. Patch version bumps and their internal dependency
constraints stay on that branch. Bring applicable release notes and general
source/test fixes to master while retaining its `X.Y.0` metadata. Only the newest
release branch is supported.

The tag-triggered workflow verifies the tag, source commit and newest
`haveapi-X.Y` branch. It fetches remote master and requires a numeric `X.Y.Z`
VERSION with patch zero and a major/minor line at least as new as the release.
Master `0.31.0` therefore permits a `0.31.2` release; a higher master line is also
valid. Release tags need not be ancestors of master, since backports can have
different ancestry. Missing master metadata or a failed fetch stops validation.

All maintained components use the shared version and are released together:

| Component | Package or destination |
| --- | --- |
| Ruby server | RubyGems `haveapi` |
| Ruby client and CLI | RubyGems `haveapi-client` |
| Go client generator, implemented in Ruby | RubyGems `haveapi-go-client` |
| Rust client generator, implemented in Ruby | RubyGems `haveapi-rust-client` |
| TypeScript client generator, implemented in Ruby | RubyGems `haveapi-typescript-client` |
| JavaScript and TypeScript client | One npm `haveapi-client` package with both clients and TypeScript declarations; a JavaScript browser bundle |
| PHP client | Composer `haveapi/client`, through `vpsfreecz/haveapi-client-php` |
| Python client | PyPI `haveapi-client` |

`CallbackClient` (also available as `Client`) and `AsyncClient` share the same
JavaScript package and version.

The Elixir server and client are unmaintained and excluded from releases.
Consumers keep their existing package names and installation commands. Release
automation does not change API behavior, data formats or deployment ordering.

## One-time GitHub and registry setup

Install `.github/workflows/release.yml` on master and the supported release
branch before tagging an automated release. A tag uses the workflow in its own
source revision.

1. Under **Settings → Environments**, create `release` and enable **Required
   reviewers**. Select the maintainers allowed to approve publication. One
   reviewer approves the publishing job; **Prevent self-review** optionally
   requires someone other than the person who pushed the tag. Restrict deployment
   to tags matching `v*`. Disable administrator bypass if that is the desired
   repository policy. The workflow checks that required reviewers are configured;
   merely naming an environment does not enable approval.
2. Configure a [RubyGems trusted publisher](https://guides.rubygems.org/trusted-publishing/)
   for each of the five gems: owner `vpsfreecz`, repository `haveapi`, workflow
   filename `release.yml`, environment `release`. For a gem that does not exist
   yet, such as the first `haveapi-typescript-client` release, use your account's
   [pending trusted publishers](https://rubygems.org/profile/oidc/pending_trusted_publishers)
   page. Enter the gem name and the same GitHub fields; leave the optional
   Workflow Repository fields blank because the workflow lives in HaveAPI.
   The first successful upload creates the gem, adds the configuring account as
   its owner and converts the pending entry into a normal publisher. No manual
   seed upload or stored RubyGems token is needed.
3. Configure the [npm trusted publisher](https://docs.npmjs.com/trusted-publishers/)
   for `haveapi-client` with the same owner, repository, workflow and environment.
   Allow direct `npm publish`; the default permission for staged publishing does
   not authorize this workflow's direct upload. A new publisher entry must
   complete its first successful publication within two days or it expires, so
   configure it close to the approved release. Confirm an existing entry remains
   valid. The package's repository URL must identify
   `https://github.com/vpsfreecz/haveapi`. The Nix release shell supplies Node 24;
   npm requires Node 22.14.0 or newer and npm 11.5.1 or newer for trusted
   publishing. Use GitHub-hosted runners; npm does not support self-hosted runners
   for this authentication. Registry access uses OIDC, with no stored RubyGems or
   npm publishing tokens.
4. Add a write deploy key to `vpsfreecz/haveapi-client-php`. Store its private key
   as environment secret `HAVEAPI_PHP_DEPLOY_KEY` in HaveAPI's `release`
   environment. This credential can push only to that repository. SSH verifies
   GitHub against `utils/release/github_known_hosts`; update that file only after
   verifying an upstream host-key change against [GitHub's published keys](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
5. Verify the PHP package's [Packagist push webhook](https://packagist.org/about).
   A successful mirror push and completed webhook indexing are separate events.
6. Set the HaveAPI repository Actions variable `HAVEAPI_RELEASE_ENABLED` to
   `true` after setup is complete. Tag builds fail visibly while publication is
   disabled or the release environment lacks required reviewers.
7. Configure a [PyPI trusted publisher](https://docs.pypi.org/trusted-publishers/)
   for project `haveapi-client`: owner `vpsfreecz`, repository `haveapi`, workflow
   `release.yml`, environment `release`. Before the first upload, use the intended
   initial owner's account Publishing page to add a pending publisher with
   project name `haveapi-client` and those GitHub fields. The first upload creates
   the project and converts the publisher; no manual seed upload is needed.
   A pending entry does not reserve the project name. Confirm the name can still
   be registered before publication: a 404 from the package JSON endpoint does
   not establish ownership or availability.
   The official PyPA action exchanges the job's OIDC identity for a short-lived
   upload credential; no PyPI password or API token is configured. TestPyPI needs
   its own publisher configuration.

Only the publishing job receives OIDC and repository write permissions. It uses
the top-level Nix shell with `HAVEAPI_RELEASE_TOOLS_ONLY=1`, which skips dependency
installation while publishing credentials are present.

## Preparing and publishing a version

Run release commands from the top-level `nix develop` shell.

Library dependency locks are local build inputs and are not tracked in Git.
Run `make release-deps` in the top-level shell before changing versions or
building on a fresh checkout. This prepares the component bundles, including
Rust and TypeScript, and the JavaScript and Python environments. Keep the
resulting local locks for subsequent locked checks. `make version` updates the
local package versions with Bundler's local resolution and the native uv
resolver; external dependency records must stay unchanged.

1. For a new major/minor line, run `make version VERSION=X.Y.0` on a master-based
   feature branch, update the changelog, validate and commit the metadata, then
   obtain integration authorization and integrate it into master before cutting
   `haveapi-X.Y`. For a patch, prepare the supported release branch instead.
   Keep source and release metadata changes in separate commits.
2. For a patch, run `make version VERSION=X.Y.Z` on the release branch. Update
   CHANGELOG.md using the existing
   `# <date> - version X.Y.Z` heading, followed by descriptions of changed
   components. Omit components that have no changes. Run `make release-check`
   and commit the version/changelog changes with the declared hooks enabled.
3. Fetch `origin` so the supported release branch refs are current. After
   obtaining publication authorization, push the release branch and an annotated
   `vX.Y.Z` tag. Do not move existing tags or push another release tag until this
   release has finished. The workflow serializes tagged releases.
   Local tagged validation is `ruby utils/release/cli.rb check-clean vX.Y.Z`;
   it requires the remote tag and fetches master again. The workflow performs
   the same check independently in its full-history build and publication
   checkouts.
4. GitHub Actions validates the metadata, generates Ruby server documentation,
   tests all maintained components and builds the packages in the locked Nix
   toolchain. It retains `release-<run-id>` as an Actions artifact for 90 days.
   Its manifest records source commit, version, checksums, tool versions and
   resolved dependency locks. Library dependencies are resolved during explicit
   preparation with npm, uv and Bundler, then reused for checks and packaging.
   Fresh checkouts can resolve different compatible dependency versions;
   separate complete release builds are not promised to be byte-identical.
5. Open the Actions run and inspect its test results, candidate summary and
   artifacts. Click **Review deployments**, select `release`, then **Approve and
   deploy**. This authorizes RubyGems/npm/PyPI publication and synchronization into
   `haveapi-client-php/master` with the corresponding version tag. Rejecting the
   request fails the workflow before the publishing job starts.
6. The publishing job verifies the saved files and retains them in a draft
   GitHub Release. It validates the PHP mirror and existing registry hashes
   before writing to any registry. The PyPA action uploads missing retained
   Python files, then the helper confirms their PyPI hashes. It pushes the Ruby
   client before its dependent server and Go, Rust and TypeScript generator
   gems, then publishes the npm tarball and updates the PHP mirror. It
   publishes the GitHub Release only after all destinations succeed.
7. Confirm the workflow's publication receipts and verify that the PHP version
   appears on Packagist. Packagist indexes the mirror asynchronously.

The GitHub Release contains the five gems, npm tarball, browser bundle, PHP
source archive, Python wheel and sdist, release notes and manifest. Python uses
the shared `VERSION`; `make version` updates its pyproject and lockfile, and
release checks reject a mismatch. No package is rebuilt after approval.
`make publish` directs maintainers to this workflow and exits without publishing.

## Build-only checks and local packaging

The release workflow also runs without publication on pushes and pull requests
that change release tooling or VERSION. Its **Run workflow** button is another
build-only entry point once the workflow exists on the default branch. These paths do not
enter the release environment or write to registries or the PHP repository.

For local verification in the top-level Nix shell:

```sh
make release-deps
make release-check
make release-test
make release
make test
ruby utils/release/cli.rb smoke-npm dist
ruby utils/release/rust_smoke.rb dist
ruby utils/release/cli.rb verify dist
cd clients/python && uv run --locked python utils/package_smoke.py
```

`make release` requires a clean tracked checkout and an empty `dist` directory.
Prepare dependencies with `make release-deps` before these checks on a fresh
checkout. Source-only `ruby utils/release/cli.rb check-clean` works before
preparation; `make release-check`, package building and manifest creation also
require `check-inputs` to pass for the actual local library locks.

Metadata checks reject a nonzero patch on a local master checkout. In a detached
checkout of master, run `ruby utils/release/cli.rb check-clean --master` to supply
the branch context; build-only master CI does this explicitly. Release branches
may have nonzero patches. A feature branch preparing a master bump can use the
same `--master` option before integration.

Move earlier artifacts aside before building. It generates shared documentation
for the Ruby server, builds five gems, rebuilds and packs JavaScript,
archives the tracked PHP subtree, and builds the Python wheel and sdist with uv.
It never uploads packages. Component gems use the local Ruby client, so a new
shared version need not already exist on RubyGems.
Do not commit generated server documentation or build artifacts.

Rust generator packaging includes its executable, templates, dependency lock,
documentation and embedded runtime source. The private Cargo harness and test
fixtures are excluded. The manifest records Rust tool versions and all ten
actual dependency lock texts, including ignored library locks. The generator
gem must contain its prepared Ruby lock. Tools-only restoration verifies those
packaged bytes against the original manifest without requiring or resolving a
local library lock. After writing the manifest, the build runs `rust_smoke.rb`
against the retained gem in an isolated installation, generates a saved schema
fixture and checks the copied runtime without loading generator code from the
checkout. The retained gem must declare its runtime fiddle dependency. The
extracted generator smoke activates that exact requirement from the prepared
component bundle and rejects Ruby default-gem fallback. `make test` covers Rust
generator unit tests, both runtime feature configurations and generated-client
protocol acceptance. See the [Rust packaging
guide](../../clients/rust/docs/releasing.md) for the generated crate's
independent versioning and compatibility checks.

TypeScript generator packaging includes the executable, Ruby library, templates,
README, license, Gemfile, Rakefile and gemspec. The last three files are part of
the generator's source identity and must travel with the gem. Package inspection
rejects missing, extra or changed files and checks the executable declaration,
Ruby floor and shared-client dependency. The Ruby client gem is also checked for
the exact shared schema sources. Its coordinated release must contain that API;
an older gem satisfying the same version range does not provide it.

The manifest retains the TypeScript component lock without packaging it in the
TypeScript gem. Tools-only artifact verification uses the retained lock and does
not resolve or require a local component bundle. After packaging, the build
prepares the supported published JavaScript runtime `haveapi-client@0.30.2`,
with install scripts disabled, then runs `typescript_smoke.rb`. This check
extracts both retained Ruby gems, clears inherited Ruby/Bundler load overrides,
verifies loaded paths, versions and source identities, generates a saved mounted
fixture with the packaged executable, runs `--check`, and compiles a strict
consumer of the emitted modules. The consumer uses the published runtime's
package-name declarations and adapter; it makes no API requests. This runtime
version is independent of the candidate's shared source VERSION.

To repeat only that smoke against already prepared artifacts and runtime:

```sh
ruby utils/release/typescript_smoke.rb dist /path/to/node_modules/haveapi-client
```

The runtime must be the original published 0.30.2 bundle; the smoke checks its
version and SHA-256. The release build prepares it before protected publication.
No dependency installation or extracted consumer build runs after approval.

The Rust runtime is embedded in generated clients; it is not a separately
published crates.io dependency. The `haveapi-runtime-tests` harness stays private
at its own version. HaveAPI's release workflow needs no crates.io token or
publisher registration. A consuming API's generated Rust crate has its own
release process.

The JavaScript packaging step runs gulp before `npm pack`. Gulp compiles the
TypeScript sources into `dist/haveapi-client.js` and `dist/types`; the npm archive
ships both client interfaces and their declarations together. The standalone
browser bundle uses the same JavaScript as the npm package. TypeScript consumers
resolve the declaration entry through the package's `types` field.

`make version` updates the npm manifest and both root version fields in the
ignored JavaScript lockfile; prepared-input checks require the lock's package
identity and versions to agree with `VERSION`. Package inspection validates the
exact `main`/`types` entries, nonempty declarations, README, both async guides and
`LICENSE.txt`, and checks that the standalone bundle matches the packed one.
The npm smoke check installs the retained tarball in a temporary consumer with
install scripts disabled and `NODE_PATH` unset. It imports `haveapi-client` by
package name, checks `Client === CallbackClient` and the version, constructs
both callback and async clients, then compiles a strict TypeScript consumer.
Compilation checks the transitive declarations; the compiler's file list must
resolve only the consumer, installed package declarations and standard libraries,
without checkout source or declarations.

The Ruby server packaging specs extract a gem and test its documentation routes.
They require `make doc`, which `make test` runs automatically. Direct server
`bundle exec rake build` still rejects missing or empty shared documentation.

## Partial failure and recovery

Publication across registries is not atomic. A failure can leave some packages
published and others missing. Keep the source tag, original Actions artifacts
and draft Release. Fix or diagnose the failure before rerunning jobs.

An upload can succeed before its public metadata becomes visible. Preflight
reads allow up to 60 seconds for temporary read failures. A missing version
returns after a canonical read and one cache-distinct read of the same exact
version endpoint. After upload, checks for both Python files and each gem/npm
confirmation have a ten-minute monotonic deadline. Final destination validation
shares one ten-minute deadline.
Only metadata GETs are retried, with bounded backoff and Retry-After handling;
uploads are never repeated within a confirmation loop. Each request has a total
deadline covering connection and response reading. Authentication, TLS, schema,
identity, platform and checksum errors stop immediately.

Metadata requests use `Cache-Control: no-cache`. A missing or valid incomplete
response permits one additional same-endpoint GET with a nonsecret unique query.
The extra read can avoid a cached response, but does not guarantee fresh metadata.
Logs identify the phase, package/version, attempt, elapsed time, HTTP outcome,
missing filenames and selected cache/retry headers, without response bodies or
credentials. Timeout messages distinguish accepted uploads awaiting confirmation
and later destinations that were not attempted.

Python staging remembers files with matching names and hashes for the current
preflight. If another read returns a missing version or fewer files, previously
validated files remain ineligible for upload. Combine these observations only
when choosing which original files to stage. Post-upload and final confirmation
require one complete, validated response. A withdrawn file leaves confirmation
pending; it is not uploaded again. A conflict in any response stops the operation.

A rerun uses the original tagged workflow and helpers. Older tags retain their
four-gem artifact contract; verify and republish their manifests with the
original tooling. The master-version guard applies to future tagged tooling;
recover existing releases with their original helpers, saved artifacts and
manifest. Do not retag, rebuild or republish accepted packages to add the guard.
If the correction needs changes to that source, prepare a new
patch version and obtain publication
authorization for it. Preserve the failed tag and its original artifacts.

Before resuming a failed publishing job, verify that every logged successful
upload is publicly visible with its original identity and retained artifact hash.
A missing metadata response, even from the cache-distinct read, does not prove an
earlier upload failed. Preserve uncertainty and diagnose it before deciding to
resume; do not reupload blindly, change the tag, replace artifacts or use
`skip-existing`. A matching existing version is skipped; a conflict stops.

Once these checks support recovery, use **Re-run failed jobs** for the publishing
job. **Re-run all jobs** also reuses the original artifact and skips its build/test
stage. If an early build failed before uploading artifacts, it can retry the
build. Once an artifact upload has succeeded, a rerun refuses to rebuild if
that artifact is missing or expired. Do not substitute a new build for an accepted package version.

Each destination is checked before publication. Existing gems must match the
retained SHA-256; npm must match package identity and tarball integrity. An
existing PHP tag must contain the same snapshot and HaveAPI source commit. The
workflow skips only verified matches, including the Rust and TypeScript
generator gems.
Conflicting versions, authentication errors and network errors fail visibly.
Existing PyPI filenames and SHA-256
values must match the manifest. Unexpected or changed files stop the release.
On partial Python publication, only missing original files are staged for the
PyPA action. The workflow does not use `skip-existing` or rebuild those files.
Final release completion requires both Python files with their original hashes.

If retained Actions artifacts have expired, preserve or download the draft
Release assets and their manifest for recovery. Operator-assisted recovery must
use those exact files after checking their recorded source and hashes; the
ordinary workflow does not automatically rebuild or replace missing artifacts.
If no original files remain, prepare a new version after diagnosing the failure.

The PHP preflight rejects existing tag/source conflicts, untagged master changes
and backward version updates before any gem or npm push. Its later atomic push
still refuses a conflicting concurrent update; such a race can leave partial
publication and must be diagnosed before retrying.

The PHP helper uses a clean isolated clone, preserves mirror-owned `.github`
configuration and AGENTS.md, and replaces the released library files with the
tracked PHP snapshot. It refuses untagged master changes and backward version
updates. It records the HaveAPI source commit and pushes master and the version
tag atomically without force. An unexpected mirror state needs inspection; do
not bypass the refusal or overwrite unrelated changes. A Packagist delay needs
webhook/indexing diagnosis rather than retagging.

Defective published content requires a new patch version. Never overwrite
package versions, move tags or delete accepted versions as part of recovery.
Consumers can select a previous package version through their normal package
manager. Release automation introduces no database or on-disk migration.
