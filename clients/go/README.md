# HaveAPI client generator for Go
HaveAPI-Go-Client generates a client library for accessing selected APIs built
with the [HaveAPI framework](https://github.com/vpsfreecz/haveapi).

See the [generated vpsAdmin Go client](https://github.com/vpsfreecz/vpsadmin-go-client)
for a ready-to-use client and examples.

## Installation

    $ gem install 'haveapi-go-client'

## CLI
The generator is run against an API server that the resulting client should be
able to work with. Without `--version`, generation uses the server's default
API version. The generated client has fixed routes for that version; regenerate
it to pick up API changes.

```
$ haveapi-go-client -h
Usage: haveapi-go-client [options] <api url> <destination>
        --version VERSION            Use specified API version
        --module MODULE              Name of the generated Go module
        --package PKG                Name of the generated Go package
```

For example:

```
$ haveapi-go-client https://api.vpsfree.cz ~/go/src/foo/client
```

## Usage
The generated library can then be imported in your projects. For example,
in a project with the following `go.mod`:

```
module foo
```

Import and use the generated client:

```go
package main

import (
	"fmt"
	"foo/client"
)

func main() {
	api := client.New("https://api.vpsfree.cz")
	api.SetLanguage("cs")

	action := api.Cluster.PublicStats.Prepare()
	resp, err := action.Call()

	if err != nil {
		fmt.Println(err)
		return
	}
	if !resp.Status {
		fmt.Printf("Action failed: %s\n", resp.Message)
		return
	}

	fmt.Printf("VPS count: %d\n", resp.Output.VpsCount)
}
```

Public actions need no authentication. For protected actions, configure an
existing token with `api.SetExistingTokenAuth(token)` or HTTP Basic credentials
with `api.SetBasicAuthentication(username, password)` before making the call.
`resp` contains the response envelope, `resp.Response.Cluster` contains the
namespaced output, and `resp.Output` provides direct access to that output.

## Localization

Generated clients include bundled HaveAPI client translations. Set the
language before making requests:

```go
api := client.New("https://api.vpsfree.cz")
api.SetLanguage("cs")
```

The value is sent in `Accept-Language` by default. Use
`SetLanguageHeader("X-Language")` when the API is configured with a custom
language header. Read the configured values with `GetLanguage()` and
`GetLanguageHeader()`.

## API documentation examples

The Ruby server can render examples against a configured generated Go SDK.
See [profile configuration, supported samples and verification](docs/documentation.md).
