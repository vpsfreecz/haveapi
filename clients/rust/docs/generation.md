# Snapshots and generation

Each snapshot describes the surface visible to its capture profile for a single
API version. It cannot establish that permission-filtered or plugin-specific
resources are complete. Inventory the captured resources, actions and parameters
and record unknown coverage explicitly. Do not combine unrelated users' schemas
or add fixture-only descriptions to a production snapshot.

## Snapshot format

The saved JSON envelope contains exactly these keys:

| Key | Meaning |
| --- | --- |
| `schema_format` | Snapshot format, currently `1` |
| `api_version` | Explicit API version string |
| `protocol_version` | HaveAPI protocol version, currently major `2` |
| `source_url` | Credential-free URL of the explicit version endpoint |
| `profile` | Non-secret capture profile label |
| `mount_path` | Server mount root, including leading and trailing `/` |
| `description` | Sanitized HaveAPI description |

`Snapshot.canonical` sorts object keys, indents by two spaces and writes UTF-8
with LF endings and a terminal newline. Array order remains meaningful. The
schema SHA-256 covers those exact bytes; it identifies the generated interface
in addition to the API version.

The sanitizer removes examples, labels, descriptions, validator messages and
protected default values. It preserves parameter and choice keys, machine
validators, ordinary defaults, metadata, auth headers, public OAuth discovery
and token action schemas. A field named `default`, `description` or `token`
remains a field. Protected defaults produce diagnostics without their values;
callers save these in separate provenance. Review remaining defaults before
publishing a snapshot. Never save credentials, HTTP headers/cookies or login
responses in a snapshot or provenance record.

The library entry points are:

```ruby
snapshot = HaveAPI::RustClient::Snapshot.fetch(
  url: 'https://api.example.test/v1.0/', api_version: '1.0', profile: 'public'
)
snapshot = HaveAPI::RustClient::Snapshot.load('schema/api-1.0.json')
inventory = HaveAPI::RustClient::IR.new(snapshot).inventory
HaveAPI::RustClient::Generator.new(schema: snapshot, config: config)
  .generate(output: 'src/generated', check: true)
```

Capture tools that already hold an OPTIONS envelope can use
`Snapshot.from_envelope(envelope, api_version:, source_url:, profile:,
mount_path: '/', diagnostics: [])`. This applies the same sanitizer used by
fetch. Pass a diagnostics array to retain removal notices in provenance.
Acquisition timestamps, raw capture hashes, the source revision, resolved
Ruby/Cargo locks and exact Rust toolchain belong in separate provenance.
The generated ownership manifest records schema, runtime and generator-source
digests, Ruby lock digest, configuration and the owned file inventory.

## Configuration and crate scaffold

`generator.toml` has these root keys:

```toml
crate_name = "example-client"
crate_version = "0.1.0"
license = "MIT"
edition = "2024"
rust_version = "1.95"
rustfmt_version = "rustfmt 1.9.0"
```

The crate version is independent of the API version. This generator supports
the displayed license, edition and MSRV. The formatter version above is an
example; record the exact `rustfmt --version` output for the client's chosen
formatter. `RUSTFMT` can select its executable. Generation rejects a version
that differs from the configuration.

`Generator#manifest_requirements` renders the initial Cargo manifest template.
It declares serde 1 with derive, serde_json 1, url 2.5, and reqwest 0.13.5 with
`default-features = false` and `features = ["json", "rustls"]`. Features are
`default = []` and `blocking = ["reqwest/blocking"]`. Tokio 1 with macros and
rt-multi-thread supports tests/examples. Commit the consuming crate's Cargo.lock.
Regeneration checks these requirements when the output is `src/generated`
inside an existing crate. It reports mismatches and never replaces Cargo.toml
or other handwritten package files.

## Generated interface

Resource components normalize to snake_case and join with double underscores.
For example, nested `project/task` becomes `project__task`, while the top-level
resource `project_task` keeps that name. A flat accessor binds ancestor path
arguments: `api.project__task(project_id).show(task_id)`. Arguments follow the
path template's order and accept values implementing `ToString`; the runtime
encodes each value as a single path segment. All remaining name collisions fail
with both original schema paths. Rust keywords receive a trailing underscore.
Action aliases use the same request and models.

Action modules live at `resources::<resource_path>::<action>`. They expose
`Input`, `Output`, `Meta` and `SPEC` where applicable. Object/hash input has a
unique defaultable struct with public `InputValue<T>` fields. Its initial state
is Unset. Value setters preserve zero, false and empty strings; nullable fields
also have `_null()` setters. Omitted fields stay omitted so server defaults can
apply. List input uses `Vec<Input>` through `.input(...)`, rather than setters
that could ambiguously apply to multiple items.

The request validates input before JSON serialization, then the runtime checks
required, nullable and typed values before dispatch. Datetime inputs are strings
validated using HaveAPI's ISO forms. Resource input is a nonnegative numeric ID;
portable metadata does not describe arbitrary string primary keys. Server-side
validators remain authoritative; the generator retains their metadata without
attempting to translate arbitrary Ruby regular expressions into Rust.

All ordinary output fields are optional, including fields marked required in
the description, because authorization can hide them. Missing and null output
fields both become `None`; wrong field types remain decoding errors. Extra
fields and metadata are retained. Custom values use `serde_json::Value`.
Associations retain their partial JSON maps and documented ID/label keys; they
do not imply a complete Show response or trigger a network request.

GET uses bracketed scalar query inputs. Explicit nullable null becomes an empty
query value, so nullable empty strings cannot always be distinguished from null
in GET requests. Nested Custom values and list layouts in GET queries fail
locally. DELETE, POST, PUT and PATCH send JSON object bodies, preserving input
and metadata namespaces. Body input supports objects and named lists, including
nested Custom values and explicit JSON null; an empty assembled body is `{}`.
Ordinary output `namespace=false` and unnamespaced list input are rejected
rather than guessed. Named empty object/hash output permits the server's
`response: {}` shortcut; missing namespaces remain errors for nonempty or list
outputs.

## Owned output and recovery

The generator owns only the requested output directory. It stages and formats
files before installation and records ownership in `.haveapi-generated.json`.
Existing nonempty output needs this marker; foreign files and symlinks are
refused. Regeneration removes obsolete owned files and preserves siblings such
as the handwritten facade and Cargo.toml. Never put handwritten files inside
the generated directory.

First installation uses an atomic directory rename. Replacing nonempty output
uses Linux `renameat2` directory exchange; hosts without that operation receive
an error before replacement. `--check` compares a temporary candidate without
writing the destination, its parent, or package files. A stale check exits with
an error and leaves existing contents and timestamps intact.

Keep runtime fixes in HaveAPI, regenerate each affected client from its retained
snapshot, and release that client through its own workflow. Copied runtime
source matches `runtime/src/runtime` byte-for-byte and has no path or Git runtime
dependency. Reverting a client revision restores its previous generated surface;
it cannot undo API actions that a newer client already sent.
