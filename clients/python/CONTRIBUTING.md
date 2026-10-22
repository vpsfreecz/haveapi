# Python development

Enter the repository's declared shell from the HaveAPI root:

```sh
nix develop .#client-python
cd clients/python
uv sync --locked
./utils/check.sh
```

The common check runs formatting, lint, strict source typing and unit tests.
Run an individual check with:

```sh
uv run --locked python utils/run_ruff.py format --check .
uv run --locked python utils/run_ruff.py check .
uv run --locked mypy src
uv run --locked pytest tests/unit
```

Drop `--check` from the format command to apply formatting. The same commands
run outside Nix after `uv sync --locked`, including in GitHub Actions on Python
3.11 through 3.15. The lockfile fixes development versions; package dependencies
keep compatible runtime ranges for consumers.

Ruff is pinned to 0.17.1 to match the native executable in the locked Nixpkgs.
`run_ruff.py` selects `HAVEAPI_RUFF` in Nix and checks that its version matches
the installed locked Python distribution. Elsewhere it runs the locked Ruff
executable. This avoids invoking PyPI's generic Linux ELF on NixOS and preserves
formatter parity with CI. Update the Nix input and Ruff pin together. Mypy and
pytest run from the uv environment.

The build requirement `uv_build>=0.13.0,<0.14` admits the locked Nix uv's native
build backend. A higher minimum would force that frontend to invoke a separate
generic Linux backend binary on NixOS. Other PEP 517 frontends can use the
current compatible uv_build release. No repository-root file or Git metadata is
required to build the source distribution.

The repository uses Overcommit. From the top-level `nix develop` shell, install
hooks with `bundle exec overcommit --install`. Inspect changed configuration or
custom hooks before signing with `bundle exec overcommit --sign` and
`bundle exec overcommit --sign pre_commit`. Python changes run the shared Ruff
entrypoint; existing Ruby, PHP and translation hooks remain enabled.

The generic integration suite starts the real Ruby HaveAPI test server on an
ephemeral loopback port, waits for readiness and health, resets fixture state
per test, and terminates its own process on completion or startup failure.
Its Python-owned shim adds GET dense-row and DELETE input/metadata echo actions
without changing the shared server. The parser-only test uses HTTPX's final
query bytes with the installed `Rack::Utils.parse_nested_query`; it also checks
that unsupported GET shapes fail before action I/O. Run it with
`uv run --locked pytest tests/integration/test_rack_wire.py`. It launches a Ruby
parser subprocess and does not start an API server. See the README for the
lossless GET subset, DELETE JSON encoding and JSON root-object restriction.

`uv run --locked pytest tests/integration/test_mounted_description.py` checks
real mounted action and token descriptors using `Rack::MockRequest` and the
shared documentation fixture. It starts no listener, leaves the server's routes
unchanged, and checks Python URL binding against the resulting OPTIONS response.
It uses the same Ruby server bundle as the parser-only check.

Install its dependencies from the repository root before running it:

```sh
nix develop
cd servers/ruby && bundle install
cd ../../clients/python
uv run --locked pytest tests/integration/test_ruby_server.py
uv run --locked python utils/package_smoke.py
```

Package smoke checks build a wheel and sdist, rebuild the extracted sdist in a
temporary directory without the repository, and install both wheels into fresh
environments. They verify the installed package version and `py.typed` marker.
They resolve runtime dependencies from the package index and require network
access. Disposable vpsAdmin integration has its own explicit bridge setup; it is
not required for a standard Python checkout or the generic CI job.

The optional vpsAdmin bridge requires `HAVEAPI_VPSADMIN_EVIDENCE_DIR` to name an
existing directory. Failed scenarios write `vpsadmin-<scenario>-<mode>-failure.log`
there with mode 0600. These bounded logs contain only the test identity, known
source locations and allowlisted exception types. Messages, source lines, local
values and fixture credentials are excluded. Private child output and manifests
are removed after each scenario.

Python follows the repository's shared `VERSION`. Use root
`make version VERSION=X.Y.Z` for an authorized release preparation; it updates
pyproject and uv.lock with the other maintained clients. See the repository
[release procedure](../../doc/agent-instructions/releases.md).
