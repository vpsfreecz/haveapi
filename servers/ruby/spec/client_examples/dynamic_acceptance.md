# Dynamic example verification

The six JavaScript, TypeScript and Python variants are ordinary server renderers.
They require no API client profile. Their examples use exact public lookups,
mounted base URLs and explicit API versions. Credentials are public example
literals: `user`, `secret`, `example-token` and `example-access-token`. Examples
do not execute during a documentation request.

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
Python async fragments are parsed in an async function. Prepare the JavaScript
build and its declared development dependencies first. The Rack fixture check
renders real mounted HTML and verifies extraction and request/result fixtures;
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

Token-login examples use advertised typed literal input maps. Python selects
continuations through `step.next_action` and calls `step.submit(values)`;
JavaScript/TypeScript use their actual action callback argument. The runtime
propagates intermediate tokens. The acceptance fixture requires fixed lifetime,
credential request and verification before authenticated discovery.

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
artifact versions with the release being tested. The harness installs the
supplied packages without checkout imports and starts its disposable mounted
fixture. It extracts examples from the overview, authentication and selected
nested-resource pages, requesting thorough detail. Each group's escaped
`data-example-details` map selects thorough when declared and Simple otherwise.
Missing or malformed declarations, duplicate panels, limitations and missing
code fail the run.

The fixture selects exactly 36 panels: six variants, each with initialization,
Basic, token, OAuth2, successful action and failed action. Eight callback
JavaScript/TypeScript initialization and provider panels are Simple; the other
28 are thorough. The harness compiles TypeScript with strict checking and runs
the exact extracted code with the installed clients. It preserves source,
including its stdout messages. This does not establish complete-program
acceptance of all Simple action fragments.

Checks cover discovery, Basic/existing token/OAuth credentials, a deterministic
token challenge, success/failure and request receipts. Receipts preserve exact
names, path order, Unicode, nested Custom values, omission, null, empty strings,
false and zero. Output and extracted programs remain in the evidence directory.
The fixture stops and the disposable consumer is removed when the operation
exits.

Each snippet's output is saved before completion checks, including nonzero
exits. Each of the 36 programs has its own before/after receipt snapshot and
saves its action/event delta beside the log. The six token-auth programs each
complete their challenge flow in that run. The fixture receipt endpoint returns
separate `actions` and `events` collections. Events contain only method, path,
status, provider/authenticated state and token request/verification completion.
They exclude credentials, tokens, challenge values, headers, queries and extra
request bodies. `fixture.log` records method, path and status.

Simple callback initialization and authentication code omits success-only
stdout markers. Completion requires successful mounted/versioned OPTIONS
discovery, authenticated through the expected provider where applicable.
Anonymous discovery alone is insufficient for authentication examples. Each
token program requires ordered request, verification and authenticated-discovery
events from that run. The twelve protected action programs require existing-token
authentication and discovery; challenge events cannot substitute for that proof.

The harness requires stdout markers where the selected source emits them, and
rejects failed callbacks or nonzero processes. Action samples retain exactly
one receipt, exact path/input values and DOC_SUCCESS/DOC_FAILURE.
`result.json` records group, variant and panel IDs with requested/effective
detail for all 36 programs, including `challenge_completions: 6`.

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
examples use the actual invocation receipt. Operation waiting uses the client's
existing API; a timeout does not cancel the server operation.
