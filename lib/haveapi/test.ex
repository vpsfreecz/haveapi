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
      make_conn(method, path, ns, payload),
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
        opts[:input]
      ),
      plug_opts
    )

    %{conn | resp_body: Poison.decode!(conn.resp_body)}
  end

  defp make_conn(method, path, ns, payload) do
    conn = conn(method, path, params_or_body(ns, method, payload))

    if method != :get && payload do
      put_req_header(conn, "content-type", "application/json")

    else
      conn
    end
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

  defp params_or_body(_, _, nil), do: nil

  defp params_or_body(ns, :get, payload) do
    payload
      |> Enum.map(fn {k,v} -> "#{ns}[#{k}]=#{v}" end)
      |> Enum.join("&")
  end

  defp params_or_body(ns, _, payload), do: Poison.encode!(%{ns => payload})
end
