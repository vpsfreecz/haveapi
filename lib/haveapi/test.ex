defmodule HaveAPI.Test do
  @path_params_rx ~r{:([^/]+)}

  use Plug.Test

  defmacro __using__(__opts) do
    quote do
      import HaveAPI.Test
    end
  end

  def call_api(api, method, path, ns \\ nil, payload \\ nil, opts \\ []) do
    plug_opts = api.init(opts)

    conn = api.call(
      make_conn(method, path, ns, payload, opts),
      plug_opts
    )
    %{conn | resp_body: Poison.decode!(conn.resp_body)}
  end

  def call_action(api, resource_name, action_name, opts \\ []) do
    plug_opts = api.init([])

    version = if opts[:version] do
      Enum.find(api.versions, &(&1 == opts[:version]))
    else
      api.default_version
    end

    resource = Enum.find(version.resources, &(resource_name == &1.name))
    action = Enum.find(resource.actions, &(action_name == &1.name))
    path = Path.join([api.prefix, "v#{version.version}", resource.route, action.route])

    conn = api.call(
      make_conn(
        action.method,
        resolve_path_params(path, opts[:params]),
        resource.name,
        opts[:input],
        opts
      ),
      plug_opts
    )

    %{conn | resp_body: Poison.decode!(conn.resp_body)}
  end

  defp make_conn(method, path, ns, payload, opts \\ []) do
    {path, body} = params_and_body(method, path, ns, payload)
    conn = conn(method, path, body)

    conn = if method != :get && payload do
      put_req_header(conn, "content-type", "application/json")

    else
      conn
    end

    conn
  end

  defp resolve_path_params(path, nil) do
    if Regex.match?(@path_params_rx, path) do
      raise "unresolved path parameters in '#{path}'"

    else
      path
    end
  end

  defp resolve_path_params(path, []) do
    if Regex.match?(@path_params_rx, path) do
      raise "unresolved path parameters in '#{path}'"

    else
      path
    end
  end

  defp resolve_path_params(path, [p | params]) when is_list(params) do
    resolve_path_params(
      Regex.replace(@path_params_rx, path, "#{p}"),
      params
    )
  end

  defp params_and_body(_method, path, _ns, nil), do: {path, nil}

  defp params_and_body(:get, path, ns, payload) do
    query_string = payload
      |> Enum.map(fn {k,v} -> "#{ns}[#{k}]=#{v}" end)
      |> Enum.join("&")

    {path <> "?" <> query_string, nil}
  end

  defp params_or_body(_method, path, ns, payload) do
    {path, Poison.encode!(%{ns => payload})}
  end
end
