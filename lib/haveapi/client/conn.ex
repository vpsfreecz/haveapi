defmodule HaveAPI.Client.Conn do
  @enforce_keys [:url]
  defstruct [
    :url,
    :version,
    :description,
    :resource_path,
    :resource_desc,
    :action_name,
    :action_desc,
    :path_params
  ]

  def new(url, version) when is_binary(url) do
    %__MODULE__{url: ensure_trailslash(url), version: version}
  end

  def scope(conn, :resource, path, path_params) when is_list(path) and is_list(path_params) do
    path = Enum.map(path, &to_string/1)
    desc = Enum.reduce(
      path,
      conn.description,
      fn r, acc ->
        if Map.has_key?(acc["resources"], r) do
          acc["resources"][r]

        else
          raise "resource '#{r}' in #{inspect(path)} not found"
        end
      end
    )

    %{conn | resource_path: path, resource_desc: desc, path_params: path_params}
  end

  def scope(conn, :action, name, path_params) when is_binary(name) and is_list(path_params) do
    desc = if Map.has_key?(conn.resource_desc["actions"], name) do
      conn.resource_desc["actions"][name]

    else
      raise "action '#{name}' of resource #{inspect(conn.resource_path)} not found"
    end

    %{conn | action_name: name, action_desc: desc, path_params: conn.path_params ++ path_params}
  end

  def scoped?(conn, :resource) do
    !is_nil(conn.resource_path) && !Enum.empty?(conn.resource_path)
  end

  def scoped?(conn, :action) do
    scoped?(conn, :resource) && !is_nil(conn.action_name)
  end

  # HTTPoison (or Hackney) seems to require the trailing slash, it doesn't
  # work without it (e.g. nxdomain error)
  def ensure_trailslash(url) do
    if String.last(url) == "/" do
      url

    else
      url <> "/"
    end
  end
end
