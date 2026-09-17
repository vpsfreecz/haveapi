# Branches and releases

Required procedure selected by the repository AGENTS.md. The rules retain their
repository scope and precedence. Paths and commands below are relative to the
repository root unless explicitly stated otherwise.

## Branches
- `master` branch contains the latest development version.
- When a new major/minor release is made, a new brach is created, e.g. `haveapi-0.26`. Fixes from the master are than cherry-picked (`git cherry-pick -x`) into the release branch and a new patch version is made, e.g. `v0.26.1` in branch `haveapi-0.26`.
- Only the latest release branch is supported.


## Releasing a new version
- When releasing a new major/minor version, create a new release branch.
- When releasing a patch version, work within the release branch.
- `make version VERSION=<major>.<minor>.<patch>` will update versions of all components.
- Update `CHANGELOG.md` and add a brief description of changes for each component. If there are no changes to a component, it is not mentioned.
- Always run `make release` and `make publish` from within the top-level `nix develop` shell so the correct toolchain is used; running them outside nix can produce build failures or mismatched Ruby versions.
- `make release` will build artifacts of all components. Run it inside `nix develop`.
- `make publish` will upload the built artifacts to package repositories, e.g. rubygems.org, npmjs.com, etc. Run it inside `nix develop` and always ask before publishing a new version.


## PHP client irregularity
- The PHP client at `clients/php/` must be released separately due to a restriction in `composer` -- it does not support monorepos, the PHP package is expected to live in the top-level directory.
- When releasing a new version, the contents of `clients/php/` is synchronized with another repository at `https://github.com/vpsfreecz/haveapi-client-php`.
- Synchronization is done by cloning repository `vpsfreecz/haveapi-client-php` and using rsyncto update/remove files.
- Release branches are not created in `vpsfreecz/haveapi-client-php`, since only the latest release is supported, only the `master` branch is updated.
- New version is tagged and the changes are pushed.
