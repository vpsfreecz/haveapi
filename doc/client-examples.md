# Client examples in API documentation

The Ruby server renders examples from the current user's API description.
JavaScript and TypeScript examples cover callback and async clients; Python
examples cover sync and async clients. These clients need no server configuration.
Ruby, PHP, CLI, curl and HTTP examples are also available. A sample
that a client cannot represent shows a limitation instead of dropping input or
inventing a successful result.

Go and Rust tabs require a profile for a generated SDK. Their package versions
are independent of HaveAPI and the API version. Without a profile, the server
hides those clients from the overview and all initialization, authentication and
action panels. Install the matching generator gem only when configuring its
profile; ordinary servers do not depend on either generator.

## Configure a generated SDK

Register profiles before mounting the server. For an SDK that matches the current
API, configure its package identity:

```ruby
api.documentation_clients('1.0',
  go: {
    import_path: 'example.org/widget/client'
  },
  rust: {
    crate_name: 'widget-client'
  }
)
api.mount('/api/')
```

`generator_version` defaults to the server's `HaveAPI::VERSION`. Install the
optional `haveapi-go-client` or `haveapi-rust-client` generator gem at that
version. An explicit `generator_version` requires the installed generator to
report that version; it never downloads one. It is independent of the SDK and
API versions.

At the end of mount, the server builds one private structural model per configured
API version. The model includes authentication resources, routes and changes from
post-mount hooks, so canonical names and parent arguments use the complete API
declaration. The private copy excludes examples, prose and parameter defaults.
HTML requests use the current user's authorized description, fields and samples;
they never expose the private model or its initialization diagnostics. Without
a configured profile, the server loads no optional generator and shows no Go or
Rust panels.

Automatic profiles assume that the installed SDK matches the current server's
generation contract. A package name or version does not prove its contents.
An older SDK can lack new actions or use different names after a collision or
route change. Check actual SDK compatibility before advertising it; use a saved
schema override below when the SDK represents an older or restricted API.

### Optional SDK versions and sources

Set `module_version: 'v1.2.3'` for Go or `crate_version: '1.2.3'` for Rust when a
specific package version is needed. Omit the field or use nil to let the user's
package manager select a release. The server does not query a registry or claim
to have resolved a version. Omitted versions produce these installation hints:

```sh
go get example.org/widget/client@latest
cargo add widget-client
# Blocking Rust variant:
cargo add widget-client --features blocking
```

Go resolves `@latest` by its normal rules. Cargo selects a compatible release
according to its resolver, manifest and toolchain; existing lockfiles still
apply. Explicit Cargo versions remain version requirements, without an added
exact `=` pin. Latest selection can change over time; supply a version to control
the selection. Cargo never receives a literal `version = "latest"`. Rust
examples also show their Tokio and serde_json requirements.

For an unpublished Rust SDK, supply an HTTPS Git URL and a full commit SHA:

```ruby
api.documentation_clients('7.0',
  rust: {
    crate_name: 'vpsadmin-client',
    source: {
      git: 'https://github.com/vpsfreecz/vpsadmin-rust-client',
      rev: 'ff876abe17e3301da62c1b6afbda055ec89db9d2'
    }
  }
)
```

The dependency hint uses that source instead of a registry release:

```toml
# Cargo.toml
vpsadmin-client = { git = "https://github.com/vpsfreecz/vpsadmin-rust-client", rev = "ff876abe17e3301da62c1b6afbda055ec89db9d2" }
# The blocking variant also sets features = ["blocking"].
```

`source` accepts only `git` and `rev`. URLs must be absolute HTTPS without
credentials, query strings, fragments or control characters; revisions must be
40 hexadecimal characters. Branches, tags, local paths and custom registries are
not supported. An explicit crate version additionally constrains the selected
source package. The server never fetches the repository or runs these user
installation commands. These settings do not regenerate or publish an SDK and
do not establish that this particular SDK matches a given API surface.

### Saved-schema overrides

The existing file-based profiles remain supported:

```ruby
api.documentation_clients('1.0',
  go: {
    import_path: 'example.org/widget/client',
    module_version: 'v1.2.3',
    description_path: '/srv/widget-sdk/api-1.0.json',
    generator_version: '0.30.0'
  },
  rust: {
    snapshot_path: '/srv/widget-sdk/api-1.0.snapshot.json',
    generator_config_path: '/srv/widget-sdk/generator.toml',
    generator_version: '0.30.0'
  }
)
```

Paths name trusted absolute local files. `description_path` is Go's saved
machine-readable description, not HTML. `snapshot_path` is Rust's saved schema
and capture metadata. They select an exact SDK shape in place of the current
server declaration. Keep the files private and retain them with the SDK release.

Rust's legacy `generator_config_path` supplies the crate name/version and full
packaging configuration. It is mutually exclusive with inline `crate_name` and
`crate_version`, and can be paired with either a saved snapshot or automatic
schema. A saved snapshot can instead use inline crate identity. `source` works
with either identity form. The server validates the full legacy TOML; normal
inline documentation needs no license, compiler or formatter settings.

Saved files are read and validated during registration. Automatic models are
initialized at the end of mount. Missing files or generators, actual generator
version mismatches, unknown fields, conflicting identities and invalid schemas
fail startup. Mounting also rejects unavailable API versions and mismatched Rust
snapshot versions. Failed mounting publishes no profiles and leaves no usable
server application. An older explicitly pinned generator can serve a suitable
legacy file profile, but automatic/inline Rust mode requires the new factory
interface and never guesses a fallback.

A saved SDK can still serve examples after unrelated live additions. Each sample
must match its saved route, layout and supplied parameter contracts; unavailable
or stale samples show a limitation. Hidden actions, fields, defaults and samples
remain hidden from the current user. The server never fetches descriptions,
regenerates packages or runs a compiler/formatter during an HTML request.

Old profile settings work on the new server. Inline settings require the new
server code; rolling back that code also requires restoring compatible settings.
Mixed server workers can show different documentation examples without changing
wire requests or persisted data.

## Renderer extensions

Existing renderer positional constructors and `init`, `auth(method, desc)` and
`example(sample)` or `request(sample)`/`response(sample)` methods still work.
The registry binds a request-local `HaveAPI::ClientExample::Context` through
`with_context`. It holds the selected version, URLs including the API mount,
the filtered description, and the current resource, action and sample.
Construction copies and freezes Hash, Array and String data without freezing
the caller's containers. Each request owns its description snapshot.
`context.with(...)` creates a distinct frozen context, sharing unchanged fields
by identity and normalizing only explicitly supplied fields. A shallow-frozen
input container still needs copying; explicitly supplying an existing owned Hash,
Array or String also copies it. Renderers must treat context-owned data as
read-only.

The profile is a shared reference; registered profiles and their adapters are
frozen separately. Other object types retain their existing reference semantics,
so context construction is not an arbitrary-object deep-freezing contract.
Subclasses of `Context` continue deriving through their constructors, preserving
custom initialization and extra keywords; the sharing optimization applies to
the exact base class.

Renderers may return a String or nil through their existing methods. New
renderers return either `{status: :code, code: source}` or
`{status: :limitation, reason: text}`. Source and limitation text are plain
strings, escaped once by the templates. A stable class `id` identifies a
variant; `code` selects its syntax language. `available?(context)` controls the
overview and every panel before rendering.

Generated-client adapters belong to their generator gems and consume context
readers without depending on the server gem. They resolve names using the
complete private generator model and never run a compiler, formatter or generator
in an HTML request. Keep adapter rendering read-only: configured adapters are frozen
and shared, while authorized description snapshots belong to individual requests.
Derived contexts within one request share unchanged owned data. Supplying a
resource, action or sample still copies that supplied subtree, so a resource with
many actions can remain costly to render.

## Verification

`make test-documentation` checks renderers, contexts, profiles, rendered HTML and
local assets. Prepare the component bundles and JavaScript development
dependencies with `make release-deps` first. The target builds the JavaScript
package before compiling TypeScript examples against its public declarations;
the Ruby server CI uses the same order.

`make test-documentation-python` additionally checks the Python renderer limits
against the real request encoder. It requires the locked Python environment
prepared by `make release-deps` and is included in `make test`. The ordinary
Ruby renderer checks run without the Python package environment.

Deterministic context and HTML regressions run in the ordinary server suite.
They check description sharing, allocation growth and isolation between users
without a wall-clock threshold. The Rust adapter suite separately checks that
normalization avoids unrelated description descendants.

### Documentation benchmark

Prepare the server bundle in its declared Nix environment, then run the opt-in
harness from the repository root:

```sh
nix develop .#server-ruby --command bash -c \
  'make --no-print-directory benchmark-documentation > /tmp/documentation.json'
```

The target synchronizes shared documentation before running the harness. Standard
output is JSON; shell/dependency preparation happens before the redirected command.
No network server, database, generated SDK compilation or formatter is involved.
The synthetic fixture uses Basic users `admin` and `member`, both with the local
test password `fixture-only`.

Defaults measure two shapes with eight ordinary actions each: eight resources
with one action, and one resource with eight actions. Each ordinary action also
has a privileged sample; the first resource has an additional admin-only action.
Context lanes derive a prepared parent with a changed profile or a constant small
sample. The HTML lane performs one real Rack request per trial, with all available
dynamic renderer panels. Use a minimal smoke run or a larger repeated campaign:

```sh
make benchmark-documentation \
  BENCHMARK_DOCUMENTATION_ARGS='--shape resources --size 1 --warmup 0 --trials 1 --iterations 1'
make benchmark-documentation \
  BENCHMARK_DOCUMENTATION_ARGS='--shape both --size 64 --samples 2 --parameters 8 --warmup 2 --trials 7 --iterations 500' \
  > /tmp/documentation-large.json
```

Run these `make` commands inside the prepared shell. `--shape custom --resources
N --actions N` controls both dimensions independently; `--lanes context` isolates
derivation and `--lanes html` isolates requests. `--user member` selects restricted
help. `--help` lists all options. `--rust` enables the fixture's matching Rust
profile, includes both Rust variants in HTML, and adds separate async/blocking
action and authentication adapter lanes. It requires the optional generator's
Ruby dependencies to be available; ordinary benchmark runs need none of them.
Prepare both component environments using `nix develop .#server-ruby` and
`nix develop .#client-rust`. The server bundle alone does not activate the Rust
dependencies. In the top-level Nix shell, combine the prepared local gem stores:

```sh
env -u RUBYOPT -u RUBYLIB -u BUNDLE_BIN_PATH -u BUNDLE_GEMFILE \
  -u BUNDLE_LOCKFILE -u BUNDLE_PATH -u BUNDLE_FROZEN -u BUNDLER_SETUP \
  GEM_PATH="$PWD/.gems:$PWD/clients/rust/.gems:$(ruby -e 'puts Gem.default_dir')" \
  make benchmark-documentation BENCHMARK_DOCUMENTATION_RUBY=ruby \
  BENCHMARK_DOCUMENTATION_ARGS='--rust --shape both --size 8 --warmup 1 --trials 3 --iterations 100' \
  > /tmp/documentation-rust.json
```

This command runs outside Bundler and records the gem versions actually
activated. Retain that list alongside both component locks and use the same
prepared inputs for both revisions. Missing optional dependencies fail the run;
Rust lanes are never silently omitted. See the
[Rust adapter guide](../clients/rust/docs/documentation.md#verification).

Every lane reports each trial and the median wall seconds, process CPU seconds
and allocated objects, with the operation count per trial. Wall time uses a
monotonic clock. A full GC runs before each trial, outside its timer; GC triggered
by the measured work remains included. Mount/profile construction has separate
setup metrics. Ownership construction, description selection, warmups, output
validation, hashing and JSON serialization are outside lane measurements.
Reports include fixture dimensions, renderer IDs, profile mode, Ruby runtime,
host, Git HEAD/status/diff digest, loaded source digests, dependency versions and
available lockfile/harness/fixture digests. HTML and Rust outputs include status, bytes and
SHA-256; failed or missing output causes a nonzero exit.

For a before/after comparison, retain one exact harness and fixture and point
them at each implementation with `--source-root /absolute/checkout`. Set up
equivalent dependencies and runtime first. An explicit `--source-revision LABEL`
can supplement the detected HEAD and is required for an exported source tree.
Retain exact heads, commands, raw JSON, lock/input identities and host identity.
Compare dimensions, renderer modes, statuses, bytes and body digests before
comparing medians. Context `description_shared` deliberately distinguishes the
old copying implementation. Investigate any output difference; record exact
volatile-field normalization if needed rather than silently dropping mismatches.

These measurements describe the synthetic workload on the recorded host. They
do not establish production latency. The opt-in harness has no timing threshold;
the [paired endpoint performance suite](performance.md) supplies required
quick/weekly CI timing, allocation and query gates, including documentation
OPTIONS and both HTML shapes. It retains baseline/self noise and blocks
inconclusive results. Ownership, traversal and allocation regressions cover this
failure class, while concentrated-resource costs and other future regressions
still need representative measurements.

Each client also has acceptance commands that check executable snippets against
installed packages or a generated SDK. These use
rendered source against disposable fixtures; syntax checks alone do not
establish that client calls or authentication work. See each client's
development documentation for its test environment. Highlighter rebuilding is
described in [utils/highlight](../utils/highlight/README.md).
