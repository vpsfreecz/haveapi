defmodule HaveAPI.Client do
  alias HaveAPI.Client

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

  def resource(_conn, name_or_path, path_params \\ [])

  def resource(conn, name, path_params) when is_binary(name) or is_atom(name) do
    resource(conn, [name], path_params)
  end

  def resource(conn, path, path_params) when is_list(path) do
    Client.Conn.scope(conn, :resource, path, path_params)
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
