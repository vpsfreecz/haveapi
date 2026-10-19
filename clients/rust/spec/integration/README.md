The integration suite generates a temporary client from a real HaveAPI server,
then exercises its generated builders and copied runtime. The same Rust cases
run with async and blocking clients. Scripted HTTP responses cover wire shapes
that a correct server normally does not emit. The fixture description uses API
1.0 and is separate from the public vpsAdmin API 7.0 snapshot.

Prepare dependencies with `nix develop .#client-rust --command true` and
`nix develop .#server-ruby --command true` from the HaveAPI root. This only
installs tools and gems. The fixture launcher uses the server's Gemfile and
root `.gems` directory, while generation uses the Rust component's environment.
The runner activates the component bundle itself and starts the child with a
separate server bundle that retains Ruby's default gems.

The launcher contract specs run without servers or Rust compilation:

```sh
nix develop .#client-rust --command bundle exec rspec \
  clients/rust/spec/integration/bundle_activation_spec.rb \
  clients/rust/spec/integration/fixture_actions_spec.rb \
  clients/rust/spec/integration/fixture_contract_spec.rb
```

From the HaveAPI root, run:

```sh
HAVEAPI_RUST_INTEGRATION=1 nix develop .#client-rust --command \
  ruby clients/rust/spec/integration/run.rb
```

The runner starts its own ephemeral loopback server, fetches explicit API 1.0
metadata, uses the generator's manifest requirements, generates and checks the
client, and runs Cargo tests with the blocking feature. It repeats at `/` and
`/mounted/api/`. A temporary crate and its owned server are removed on exit;
failed server startup retains a private diagnostic log and prints its path.
Generation and tests require no production credentials. Ordinary unit specs do
not invoke this runner.

Coverage includes omitted/null/value input, zero/false/empty strings, JSON
bodies, GET query namespaces, unnamespaced object input, list input/output,
Custom JSON, nested paths, object/list metadata, action-state references,
partial associations, Basic and existing OAuth2/HaveAPI tokens, explicit
TOTP/password-reset continuation, unknown steps, renew/revoke and deadlines.
Synthetic responses cover malformed/status/error envelopes, empty output,
typed decode failures, redaction, redirects and size limits. Blocking bridge
cases keep construction, use and destruction inside `spawn_blocking` under both
Tokio runtime flavors. Server mutations affect only in-memory fixture data.
The real DELETE case checks explicit null, zero, false, empty string, an omitted
field, nested Custom JSON and both input metadata channels, paired with a GET
query control.

For actual vpsAdmin acceptance, `run_vpsadmin.rb` composes fixture startup and
the generated client's own `real_vpsadmin` test target. It requires a vpsAdmin
source checkout and a generated-client checkout; it edits neither. Prepare the
source dependencies from its root with
`VPSADMIN_PLUGINS=all nix develop .#api --command true`. MariaDB, Ruby 3.4,
Bundler and fixture gems come from that API shell. No cluster, node daemon,
production database or production API is used.

```sh
VPSADMIN_REAL_INTEGRATION=1 ruby clients/rust/spec/integration/run_vpsadmin.rb \
  --source-root /path/to/vpsadmin \
  --client-root /path/to/vpsadmin-rust-client \
  --artifacts /path/to/private-artifacts
```

The source launcher refuses an inherited `DATABASE_URL`, creates a new private
MariaDB instance with `tools/test_db`, and boots the canonical API spec support
and seeds. All plugins are enabled, including WebUI user settings for Custom
JSON. It seeds a VPS named `rust-fixture-vps`, a DNS A record with TTL 120,
and ordinary fixture users. Basic `admin`/`secret` credentials are local test
data. The client tests use the public saved API 7.0 description without local
schema additions. An API update may enqueue a local transaction; acceptance
does not claim that a node executed it.

The database state uses a unique directory with mode 0700 under `/tmp` so its
Unix socket fits the platform path limit even when artifact paths are long.
Diagnostic logs remain in the selected private artifact directory.

The child emits `VPSADMIN_FIXTURE_READY` followed by a JSON object containing
`base_url`, `api_version`, `vps_id`, `dns_record_id`, `user_id`,
`setting_namespace` and `setting_key`. The parent validates the numeric loopback
URL and IDs, then supplies `VPSADMIN_TEST_BASE_URL`, `VPSADMIN_FIXTURE_JSON` and
`VPSADMIN_REAL_INTEGRATION=1` to:

```sh
nix develop --command cargo test --locked --all-features \
  --test real_vpsadmin -- --ignored --test-threads=1
```

The client repository owns those test assertions. They cover actual VPS
show/partial update/pagination, nullable DNS TTL, nested Custom JSON and token
actions. `--ignored` is required because ordinary CI skips disposable-server
acceptance. Private fixture logs and a pass receipt remain in the selected
artifact directory. The parent terminates only its child process group; the
source launcher stops and prunes only its own MariaDB instance on exit. It
never selects the repository's shared manual test database.
