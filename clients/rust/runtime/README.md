# Embedded Rust runtime

This private crate tests the common source embedded in generated HaveAPI
clients. The generator copies only `src/runtime/` to the generated runtime
module, byte for byte. The harness manifest, lockfile and tests stay in HaveAPI;
there is no separately published runtime dependency. Runtime modules refer to
`crate::runtime`, which both the harness and generated crate re-export.

Fix common behavior here, regenerate each affected client from its saved
snapshot, and release that client through its own release process. A HaveAPI
update alone does not change an already generated or published client. Keep the
runtime source digest with generation provenance. Reverting a client package
cannot undo an API action that the server has already executed.

## Requests and validation

The generated crate supplies a fixed `ApiSpec`, action specifications, typed
inputs and outputs, and resource methods. Runtime `Request` builders borrow a
client. Async and optional blocking execution share validation, URL and payload
preparation, and envelope decoding. Both clients reuse their reqwest transport.
There is no runtime API version selection or action discovery.

`InputValue::Unset` is skipped by generated Serde fields. `Null` sends an
explicit null, and `Value` preserves empty strings, zero and false. Setters and
the public replacement input follow the same path: `Validate` runs before
serialization, including finite-float checks; `prepare` then checks described
types, required fields and nullability for input and metadata. Undescribed
parameters are rejected. Omitted values never acquire client-side defaults.

POST, PUT, PATCH and DELETE use JSON objects or named object lists, including
their separate global and object metadata namespaces. DELETE preserves explicit
JSON null and nested Custom values in the body; its input is never sent in the
query. GET uses bracketed scalar query values. Query null is encoded as an empty
value and can be indistinguishable from an empty string at the server. Nested
Custom query values and list query input are unsupported for GET and fail
locally. Unnamespaced list input and per-item input metadata are unsupported for
all methods. Custom JSON remains unrestricted in JSON bodies, subject to the
parameter's nullability.

Datetime inputs use the documented HaveAPI grammar: calendar-valid dates,
shortened times, optional seconds/fractions, and explicit timezone offsets or
`Z`. Numeric resource IDs must be nonnegative `i64` values. Path arguments are
strings, independent of resource-ID inputs; callers supply parent IDs explicitly.

The base URL is the server mount root. Mount-relative action templates preserve
that mount, including global authentication paths. Placeholder data is encoded
as one URL segment. Absolute paths/URLs, dot traversal, unsafe encoded static
segments, credentials, queries and fragments in base URLs are rejected. Empty
or dot-only path arguments are invalid.

## Responses and errors

Success requires a JSON envelope, boolean `status: true`, a successful HTTP
status, and the described response namespace and layout. Empty HTTP 204 is not
implicit success. No-output actions require `response: {}` and decode to `()`.
Named empty object/hash schemas may also accept exactly `response: {}` when
their generated `allow_empty_response` flag is set. This does not permit wrong
namespaces, null output, or missing list/nonempty output namespaces.

Generated ordinary output fields are optional; missing and null fields both
become `None`. Wrong types remain errors. `Association` retains the partial or
expanded JSON map without inferring additional fields or making requests.
Response metadata defaults to an empty object when absent; list item metadata
remains on the item. Single-object metadata is response-level. No metadata
field is universally required.

`Error` distinguishes configuration, validation, encoding, transport, HTTP,
HaveAPI, protocol, typed decoding, size-limit and auth-continuation failures.
Valid failure envelopes are parsed on any HTTP status; non-2xx never becomes
success because the envelope claims success. Transport errors expose
`is_timeout()`. `http_status()`, `server_message()` and `validation_errors()`
provide explicit diagnostic access. Server messages and parameter details can
contain sensitive data; Debug and Display omit them, URLs and bodies.

## Authentication and transport policy

Select one of Basic, an existing HaveAPI token, or an existing OAuth2 token.
The selected provider must appear in `ApiSpec`; token header names come from
that specification. Tokens are sent verbatim, without an added Bearer prefix.
Header names that override HTTP framing, routing or standard client headers
are rejected. Token values are marked sensitive in reqwest's header map.
Generated token request/challenge actions omit configured client credentials;
renew/revoke actions use them. `TokenStep::from_parts` checks final versus
transient tokens and known continuation actions. It installs no token and
performs no action automatically.

Credentials, request inputs/bodies, responses and transport state are omitted
from runtime Debug output. `SecretString` requires `expose_secret()` for access;
it does not promise memory zeroization. Generated auth outputs must also keep
their Debug output redacted.

Both transports disable redirects and automatic retries. TLS uses reqwest's
rustls feature with platform certificate verification and the aws-lc backend.
No certificate-verification bypass or arbitrary HTTP-client injection is
provided. Defaults are a 30-second request timeout, 10-second connect timeout
and 16 MiB response limit. Builders can change these positive limits and the
user agent. Bodies are capped while reading even without Content-Length.
A transport failure or timeout can follow server execution; callers must
decide how to recover without assuming a mutation was rolled back.

Blocking clients require the `blocking` Cargo feature. Construct, use and drop
them outside async runtime threads. Async callers should use the async client
or put the entire blocking lifecycle inside `tokio::task::spawn_blocking`.
Aborting an already-started blocking task does not cancel its HTTP operation;
the configured deadlines still apply. There is no `block_on` bridge.

## Development checks

Use the repository's `nix develop .#client-rust` shell. This crate uses
edition 2024, MSRV 1.95 and the same dependency/feature requirements as generated
clients. The committed Cargo.lock fixes the harness dependency resolution.
The repository Nix shell supplies the development compiler and formatter.
Generation records and checks the client's exact formatter version.

From the repository root, formatting is a quick check:

```sh
cargo fmt --manifest-path clients/rust/runtime/Cargo.toml --check
```

Run the runtime tests and Clippy:

```sh
cargo test --locked --manifest-path clients/rust/runtime/Cargo.toml
cargo test --locked --manifest-path clients/rust/runtime/Cargo.toml --features blocking
cargo clippy --locked --manifest-path clients/rust/runtime/Cargo.toml --all-targets --all-features -- -D warnings
```

Protocol tests cover input fidelity, validation, mounted paths, metadata,
partial associations and envelope failures. Local HTTP fixtures cover transport
parity, redirect rejection, body caps, deadlines, no retries and blocking-client
lifecycle ownership on both Tokio runtime flavors. Full generated-client,
HaveAPI-server, MSRV and packaging checks belong to the generator/integration
and generated-client suites; passing harness tests alone does not establish
those results.
