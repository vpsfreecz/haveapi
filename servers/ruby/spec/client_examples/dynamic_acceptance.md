# Dynamic example verification

The six JavaScript, TypeScript and Python variants are ordinary server renderers.
They require no generated-SDK profile. Their examples use exact public lookups,
mounted base URLs and explicit API versions. Credentials come from environment
variables in the example process; no example executes in a documentation request.

Run the focused checks in the prepared top-level Nix environment:

```sh
cd servers/ruby
bundle exec rspec spec/client_examples/dynamic_js_spec.rb \
  spec/client_examples/dynamic_python_spec.rb \
  spec/client_examples/dynamic_metadata_spec.rb \
  spec/client_examples/dynamic_acceptance_spec.rb
```

The unit checks parse the actual generated source and compile both TypeScript
variants at both detail levels against emitted public declarations. Simple
action fragments receive a declared initialized `api` in the compiler fixture;
Python async fragments are parsed in an async function. Prepare the JavaScript build and
its declared development dependencies first. The Rack fixture check renders real
mounted HTML and verifies the extraction boundary and request/result fixtures;
it opens no listening socket and does not install packages.

`make test-documentation-python` runs the supplemental native Python request
builder checks in `test_support/dynamic_protocol_spec.rb` and
`test_support/dynamic_python_login_spec.rb`. Prepare the locked Python
component environment with `make release-deps` first; the check uses
`clients/python/.venv/bin/python` and imports the checkout protocol implementation.
It cross-checks GET limitations, JSON methods and required input metadata without
transport. It installs nothing and is separate from ordinary Ruby spec discovery.
The focused JavaScript specs cross-check the built callback and async query/body
serializers with a mocked transport. The full `make test` includes both checks.

Python token-login examples read required request fields from JSON values in
`HAVEAPI_AUTH_*` environment variables. For example, an API that requires
`lifetime` reads `HAVEAPI_AUTH_lifetime`. The examples omit optional lifetime and
interval fields. The acceptance fixture explicitly chooses `"fixed"` from its
advertised lifetime values and omits optional interval. The Python challenge
object supplies the continuation token.

`dynamic_acceptance.rb` checks the installed packages. Supply the built npm and
Python artifacts, the compiler and Node declaration directories, and a directory
for evidence. Paths are absolute because the harness changes to an
isolated consumer:

```sh
cd servers/ruby
bundle exec ruby spec/client_examples/dynamic_acceptance.rb \
  --npm-artifact /absolute/path/dist/haveapi-client-0.30.0.tgz \
  --python-artifact /absolute/path/dist/haveapi_client-0.30.0-py3-none-any.whl \
  --typescript /absolute/path/clients/js/node_modules/typescript/bin/tsc \
  --node-types /absolute/path/clients/js/node_modules/@types \
  --output /absolute/path/session/dynamic-acceptance-wheel
```

Repeat with the retained Python sdist and a separate evidence directory. Replace
artifact versions with the release being tested. The test installs the supplied
packages without checkout imports, starts its disposable mounted fixture, extracts
explicitly thorough code panels from the overview, authentication and selected
nested-resource pages, compiles TypeScript with strict checking and runs
the snippets with the installed clients. It checks discovery, Basic/existing
token/OAuth credentials, a deterministic token challenge, success/failure and
request receipts preserving exact names, path order, Unicode, nested Custom
values, omission, null, empty strings, false and zero. Output and extracted
programs remain in the evidence directory. The fixture stops and disposable
consumer is removed when the operation exits.

Each snippet's output is saved before completion checks, including nonzero
exits. Token panels have separate `example-N-challenge.log` files for the login
flow without an existing token. `fixture.log` records request method, path and
HTTP status; the trace excludes headers, query strings and request bodies.

JavaScript list input and nested GET/OPTIONS query values produce a visible
limitation; HEAD input retains the client's JSON body behavior. Python GET
examples use a conservative flat-scalar subset with nonempty, bracket-free
parameter names and namespaces. Custom values must be strings or nullable nulls;
structured GET values produce a limitation even when the client supports them.
Python POST, PUT and DELETE retain supported object/list JSON input; unsupported
methods produce a limitation. Required global or object input metadata also
produces a limitation because the sample format has no metadata input channel.
Optional metadata needs no invented values. Prose-only and incomplete samples do
not become fabricated calls. Callback examples print the raw response; async
examples use the actual invocation receipt. Operation waiting is shown only through the client's existing
API, and a timeout is not a cancellation of the server operation.
