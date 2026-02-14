HaveAPI
=======
HaveAPI defines a protocol for self-describing RESTful APIs. This repository
contains documentation of said protocol and a reference implementation of both
server and client side libraries.

## What is a self-describing API?
A self-describing API knows about itself what resources and actions it contains.
It is able to send this information to clients in a machine-readable form.
The API responds to HTTP method `OPTIONS` and returns the description
of available resources, actions, their input/output parameters, labels, text
notes, data types, validators and example usage.

Clients use the self-description to learn how to communicate with the API,
which they otherwise know nothing about.

## Motivation
Whenever you create an API server, you need to implement clients in various
programming languages to work with it. Even if you make all APIs similar using
e.g. REST or SOAP, you still need clients to know what resources and actions
the API has, what are their parameters, and so on.

When your API speaks the HaveAPI protocol, you can use pre-created clients that
will know how to work with it. You can do this by using this framework to
handle all HaveAPI-protocol stuff for you, or you can implement
the [protocol](doc/protocol.md) on your own.

Available server frameworks:

- Ruby server at [servers/ruby](servers/ruby)
- Elixir server at [servers/elixir](servers/elixir) (outdated)

Available clients:

- Ruby client library and CLI at [clients/ruby](clients/ruby)
- PHP client at [clients/php](clients/php)
- JavaScript client at [clients/js](clients/js)
- Go client generator at [clients/go](clients/go)
- Elixir client at [clients/elixir](clients/elixir) (outdated)

Complex applications can be built on top of these basic clients, e.g.:

- [haveapi-webui](https://github.com/vpsfreecz/haveapi-webui), a generic web
  administration for HaveAPI-based APIs
- [haveapi-fs](https://github.com/vpsfreecz/haveapi-fs), a FUSE based filesystem
  that can mount any HaveAPI-based API

If there isn't a client in the language you need, you can
[create it](doc/create-client.md) and then use it for all HaveAPI-based APIs.

## Protocol features
- Creates RESTful APIs usable even with simple HTTP client, should it be needed
- A change in the API is immediately reflected in all clients when they re-download the
  documentation
- Generic interface for clients - one client can be used to access all APIs
  that implement this protocol
- Supports API versioning
- Standardised authentication methods
- Defines action input/output parameters and their validators
- Clients can monitor progress of long-running actions

## Read more
 - [Protocol definition](doc/protocol.md)
 - [How to create a client](doc/create-client.md)
 - [Typed input validation rules](doc/typed-input-validation.md)
 - [Project templates](templates)
 - [API examples](examples)
