defmodule HaveAPI.Client do
  alias HaveAPI.Client

  defmacro __using__(opts) do
    quote do: use HaveAPI.Client.Standalone, unquote(opts)
  end

  def new(url, version \\ nil) when is_binary(url) do
    Client.Conn.new(url, version)
  end

  def setup(conn) do
    %{conn | description: Client.Protocol.describe(conn)}
  end

  def connect(url, version \\ nil) do
    url
    |> new(version)
    |> setup
  end

  def authenticate(conn, :basic, username, password) do
    Client.Authentication.setup(
      conn,
      Client.Authentication.Basic,
      username: username,
      password: password
    )
  end

  def authenticate(conn, :basic, opts) do
    Client.Authentication.setup(
      conn,
      Client.Authentication.Basic,
      opts
    )
  end

  def authenticate(conn, :token, token) when is_binary(token) do
    Client.Authentication.setup(
      conn,
      Client.Authentication.Token,
      token: token
    )
  end

  def authenticate(conn, :token, opts) when is_list(opts) do
    Client.Authentication.setup(
      conn,
      Client.Authentication.Token,
      opts
    )
  end

  def logout(conn), do: Client.Authentication.logout(conn)

  def resources(conn), do: resources(conn, [])

  def resources(conn, []) do
    Map.keys(conn.description["resources"])
  end

  def resources(conn, path) when is_list(path) do
    Map.keys(resource(conn, path).resource_desc["resources"])
  end

  def actions(conn, resource) when is_binary(resource) do
    Map.keys(conn.description["resources"][resource]["actions"])
  end

  def actions(conn, resource_path) when is_list(resource_path) do
    Map.keys(resource(conn, resource_path).resource_desc["actions"])
  end

  def resource(_conn, name_or_path, path_params \\ [])

  def resource(conn, name, path_params) when is_binary(name) or is_atom(name) do
    resource(conn, [name], path_params)
  end

  def resource(conn, path, path_params) when is_list(path) do
    Client.Conn.scope(conn, :resource, path, path_params)
  end

  def action(conn, path, name, path_params \\ []) do
    conn
    |> Client.Conn.scope(:resource, path, [])
    |> Client.Conn.scope(:action, name, path_params)
  end

  def call(conn, action, opts) do
    unless Client.Conn.scoped?(conn, :resource) do
      raise "set resource path first or use call/4"
    end

    conn
    |> Client.Conn.scope(:action, action, opts[:path_params] || [])
    |> Client.Request.execute(opts)
  end

  def call(conn, resource_path, action, opts) do
    conn
    |> Client.Conn.scope(:resource, resource_path, [])
    |> Client.Conn.scope(:action, action, opts[:path_params] || [])
    |> Client.Request.execute(opts)
  end
end
