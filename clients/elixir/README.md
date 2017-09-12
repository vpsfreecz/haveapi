# HaveAPI client for Elixir
This is a client library for [HaveAPI](https://github.com/vpsfreecz/haveapi)-based
APIs written in Elixir.

## Installation
If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `haveapi_client` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:haveapi_client, "~> 0.1.0"}]
end
```

List `:httpoison` as your application dependency:

```elixir
def application do
  [applications: [:httpoison]]
end
```

## Usage
The client can connect to any HaveAPI-based API. You can use `HaveAPI.Client.connect/2`
to connect to the API and fetch its description:

```elixir
conn = HaveAPI.Client.connect("https://api.domain.tld")
```

Both HTTP basic and token authentication is supported:

```elixir
# HTTP basic
conn = HaveAPI.Client.authenticate(conn, :basic, "user", "password")

# Token - request token using username and password
conn = HaveAPI.Client.authenticate(conn, :token, username: "user", password: "password")

# Or use previously issued token
conn = HaveAPI.Client.authenticate(conn, :token, "<token>")
```

Actions can be invoked using `HaveAPI.Client.call/3` or `HaveAPI.Client.call(4)`:

```elixir
# Call action directly
resp = HaveAPI.Client.call(conn, "myresource", "myaction", input: %{parameter: 123})

# Scope conn to specific resource
resource = HaveAPI.Client.resource(conn, "myresource")
resp = HaveAPI.Client.call(resource, "myaction", input: %{parameter: 123})
```

## DSL
The client outlined above is set up during runtime, which is useful when you want
to connect to APIs not known during compile time. However, if the API URL is known
beforehand, the client can be generated for a selected API during compile time.
The API description is compiled alongside the program and the client does not have
to fetch it during runtime.

The client dynamically generates modules for API resources and functions for
actions, so the compiler will also check that you're using the API correctly.

First, define a module and use module `HaveAPI.Client`, giving it the API URL:

```elixir
defmodule MyApi do
  # For anonymous access
  use HaveAPI.Client, url: "https://api.vpsfree.cz"

  # Or with built-in authentication
  use HaveAPI.Client, url: "https://api.vpsfree.cz", auth: {:token, "<token>"}
end
```

You can then call API actions with no further setup:

```elixir
iex> MyApi.resources
["cluster", "node", ...]

iex> MyApi.cluster.actions
["public_stats", ...]

iex> MyApi.cluster.public_stats
%HaveAPI.Client.Response{response: %{"cluster" => %{
  "ipv4_left" => 176,
  "user_count" => 1210,
  "vps_count" => 1643
}, ...}
```
