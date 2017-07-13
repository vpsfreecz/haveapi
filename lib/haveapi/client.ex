defmodule HaveAPI.Client do
  alias HaveAPI.Client

  def new(url, version \\ nil) when is_binary(url) do
    %Client.Conn{url: url, version: version}
  end

  def setup(conn) do
    %{conn | description: Client.Protocol.describe(conn, :default)}
  end

  def connect(url, version \\ nil) do
    url
    |> new(version)
    |> setup
  end

  def resource(_conn, name_or_path, path_params \\ [])

  def resource(conn, name, path_params) when is_binary(name) or is_atom(name) do
    resource(conn, [name], path_params)
  end

  def resource(conn, path, path_params) when is_list(path) do
    %{conn | resource_path: Enum.map(path, &to_string/1), path_params: path_params}
  end

  def call(conn, action, opts) do
    if is_nil(conn.resource_path) || Enum.empty?(conn.resource_path) do
      raise "set resource path first or use call/4"
    end

    call(conn, conn.resource_path, action, opts)
  end

  def call(conn, resource_path, action, opts) do
    Client.Protocol.execute(conn, resource_path, action, opts)
  end
end
