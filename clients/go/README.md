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
