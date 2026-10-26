# Go client generator

Generate a Go client for one API version from a saved [HaveAPI](https://github.com/vpsfreecz/haveapi)
protocol 2 description. Capture the schema once, review it, then generate offline.
The resulting client has fixed resource names and routes; it does not discover
API changes at runtime.

## Prepare the source tools

From the HaveAPI checkout root, enter its Nix environment and prepare the Go
component's Ruby dependencies:

```sh
nix develop
BUNDLE_GEMFILE="$PWD/clients/go/Gemfile" bundle install
```

Keep that checkout and resolved component lock with your generation inputs.
The component bundle uses the Ruby client from the same checkout. Go must also
be on `PATH` for `go fmt`.

## Fetch, save and generate

The examples assume an API at `https://example.test/v1.0/` with a `Widget#Show`
action at `/v1.0/widgets/{widget_id}` and a string `name` output. Replace the
example URL, version and resource names with those of your API.

From the HaveAPI root:

```sh
mkdir -p /path/to/widget-client/schema
BUNDLE_GEMFILE="$PWD/clients/go/Gemfile" bundle exec ruby \
  clients/go/bin/haveapi-go-client fetch https://example.test/v1.0/ \
  --api-version 1.0 --profile public \
  --output /path/to/widget-client/schema/api.json
BUNDLE_GEMFILE="$PWD/clients/go/Gemfile" bundle exec ruby \
  clients/go/bin/haveapi-go-client generate \
  --schema /path/to/widget-client/schema/api.json --api-version 1.0 \
  --output /path/to/widget-client --module example.test/widget-client --package client
```

The output directory for the saved schema must already exist. Fetch sends OPTIONS
at the exact version URL, including any mount prefix; it never selects a server
default. Generation reads the saved schema, uses the existing Go emitter and
runs `go fmt`. It does not contact the API or install dependencies. The generated
module contains the `client` package; keep handwritten application files elsewhere.

Public capture is the default. For Basic authentication, set `WIDGET_PASSWORD`
in your environment, then run:

```sh
BUNDLE_GEMFILE="$PWD/clients/go/Gemfile" bundle exec ruby \
  clients/go/bin/haveapi-go-client fetch https://example.test/v1.0/ \
  --api-version 1.0 --profile basic-user --basic-user demo \
  --basic-password-env WIDGET_PASSWORD \
  --output /path/to/widget-client/schema/api.json
```

For an existing HaveAPI token, set `WIDGET_TOKEN` and use:

```sh
BUNDLE_GEMFILE="$PWD/clients/go/Gemfile" bundle exec ruby \
  clients/go/bin/haveapi-go-client fetch https://example.test/v1.0/ \
  --api-version 1.0 --profile token-user --token-env WIDGET_TOKEN \
  --output /path/to/widget-client/schema/api.json
```

The two authentication choices are mutually exclusive. Token capture first reads
anonymous discovery at the same version URL, then uses the advertised token
header. Supply a token you have already acquired. `--profile` labels the capture;
it does not change authentication. A snapshot covers the resources visible during
capture, which depend on permissions and enabled plugins.
Review saved defaults and data before sharing the schema. Credentials and tokens
must stay out of snapshots. Failed capture preserves an existing output file.

## Use the generated client

In a separate application, use the generated module locally:

```sh
go mod init example.test/widget-app
go mod edit -require=example.test/widget-client@v0.0.0
go mod edit -replace=example.test/widget-client=/path/to/widget-client
```

```go
package main

import (
    "fmt"
    "log"
    "example.test/widget-client/client"
)

func main() {
    api := client.New("https://example.test")
    action := api.Widget.Show.Prepare().SetPathParamInt("widget_id", 1)
    resp, err := action.Call()
    if err != nil {
        log.Fatal(err)
    }
    if !resp.Status {
        log.Fatal(resp.Message)
    }
    if resp.Output != nil {
        fmt.Println(resp.Output.Name)
    }
}
```

Give `client.New` only the API origin, such as `https://example.test`, without
a trailing slash. Generated action paths already contain the mount prefix and
API version. Authentication helpers
are emitted for advertised providers; a matching schema can use
`SetBasicAuthentication(user, password)` or `SetExistingTokenAuth(token)`.
Permissions and server validation still apply. `resp` retains the response
envelope; `resp.Output` provides the action output directly.

Set `api.SetLanguage("cs")` to send `Accept-Language`.
`SetLanguageHeader("X-Language")` selects a custom header; `GetLanguage()` and
`GetLanguageHeader()` return the configured values.

## Legacy invocation

The positional `haveapi-go-client [options] URL DESTINATION` command remains
available. Its optional `--version` still defaults to the server's default
version; `--basic-user` and raw `--basic-password` retain their old meaning.
Use the saved-schema workflow above for explicit, repeatable generation and
secrets supplied through environment variables.

The Ruby server can render examples for configured generated clients; see
[documentation profiles](docs/documentation.md).
