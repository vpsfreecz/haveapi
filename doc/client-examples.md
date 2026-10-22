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

Register profiles before mounting the server. Paths must name trusted absolute
local files. Keep the SDK's saved description and generator configuration;
the server does not fetch descriptions or regenerate SDKs while serving docs.

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
api.mount('/api/')
```

Use the SDK's published package name and version. The Rust crate name and
version come from the generator TOML configuration, which also records the
formatter and language requirements. Go uses the import alias `client`. The
installed generator version must match the profile. Missing files or adapters,
unknown fields, duplicate profiles and invalid SDK schemas or configurations
cause startup to fail. Mounting also rejects profiles for unselected API
versions and Rust snapshots bound to another API version.

An SDK profile can still serve examples after unrelated additions to the live
API. Each example is checked against the SDK's saved action, route, layout and
parameter contract. An unsupported or stale sample produces a limitation.
Profiles do not expose actions, fields, defaults or samples hidden from the
current user. The full SDK schema and local paths stay private; request
contexts use only the current user's filtered description and the selected
sample.

## Renderer extensions

Existing renderer positional constructors and `init`, `auth(method, desc)` and
`example(sample)` or `request(sample)`/`response(sample)` methods still work.
The registry binds a request-local `HaveAPI::ClientExample::Context` through
`with_context`. It holds the selected version, URLs including the API mount,
the filtered description, and the current resource, action and sample.
`context.with(...)` creates another frozen copy without freezing the server's
shared description.

Renderers may return a String or nil through their existing methods. New
renderers return either `{status: :code, code: source}` or
`{status: :limitation, reason: text}`. Source and limitation text are plain
strings, escaped once by the templates. A stable class `id` identifies a
variant; `code` selects its syntax language. `available?(context)` controls the
overview and every panel before rendering.

Generated-client adapters belong to their generator gems and consume context
readers without depending on the server gem. They resolve names using the
saved generator schema and never run a compiler, formatter or generator in an
HTML request. Keep adapter rendering read-only: configured adapters are frozen
and shared, while filtered contexts are copied per request.

## Verification

`make test-documentation` runs focused renderer/context/profile/HTML checks and
local asset checks. Each client also has acceptance commands that check
executable snippets against installed packages or a generated SDK. These use
rendered source against disposable fixtures; syntax checks alone do not
establish that client calls or authentication work. See each client's
development documentation for its test environment. Highlighter rebuilding is
described in [utils/highlight](../utils/highlight/README.md).
