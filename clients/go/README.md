HaveAPI Client Generator For Go
-------------------------------
HaveAPI-Go-Client generates a client library for accessing selected APIs built
with the [HaveAPI framework](https://github.com/vpsfreecz/haveapi).

## Installation

    $ gem install 'haveapi-go-client'

## CLI
The generator is run against an API server that the resulting client should be
able to work with. The generated client uses one selected API version. When
the API server changes, the client has to be regenerated.

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

The client could be imported and used as:

```go
package main

import (
	"fmt"
	"foo/client"
)

func main() {
	api := client.New("https://api.vpsfree.cz")
	api.SetLanguage("cs")
	api.SetBasicAuthentication("admin", "secret")

	action := api.Cluster.PublicStats.Prepare()
	resp, err := action.Call()

	if err != nil {
		fmt.Println(err)
		return
	}

	fmt.Printf("%+v\n", resp)
	fmt.Printf("%+v\n", resp.Response)
	fmt.Printf("%+v\n", resp.Response.Cluster)
	fmt.Printf("%+v\n", resp.Output)
}
```

## Context and raw responses

Generated action invocations provide three call methods:

- `Call()` returns the typed response using `context.Background()`.
- `CallContext(ctx)` returns the same typed response with the supplied context.
- `CallRaw(ctx)` returns `*client.RawResponse`, containing `StatusCode int` and
  `Body json.RawMessage`, without decoding the body or classifying HTTP/API status.

Actions with a direct, parameter-free `Call()` also provide `CallContext` and
`CallRaw` shortcuts. For example, use a deadline for a typed request:

```go
ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
defer cancel()

resp, err := api.Cluster.PublicStats.CallContext(ctx)
```

As an alternative to the typed call, inspect the complete response yourself:

```go
raw, err := api.Cluster.PublicStats.CallRaw(ctx)
if err != nil {
	return err
}
// Check raw.StatusCode, then decode raw.Body for the fields the caller needs.
```

Each call validates and serializes the selected inputs and dispatches once
through the configured HTTP client.
The context covers waiting for headers and reading the body. Response bodies
are closed before return, and cancellation errors retain `errors.Is` identity.
The client adds no request retry. Configure HTTP timeouts, redirects and the
transport with `SetTimeout` or `SetHTTPClient` as needed.

Raw bodies retain their received bytes, including whitespace, JSON null, large
numbers and malformed JSON. A complete HTTP error response is a raw result;
validation, transport, cancellation and body-read failures remain Go errors.
Typed calls retain the existing HTTP/API status semantics: inspect `Status`,
`Message` and `Errors`. Missing or malformed required envelopes/output containers
return errors instead of panicking. Existing low-level request helpers retain
their signatures and use a background context.

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
