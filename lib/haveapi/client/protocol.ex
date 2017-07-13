defmodule HaveAPI.Client.Protocol do
  alias HaveAPI.Client.Http

  @path_param_rx ~r{:[^/]+}

  def describe(conn, :default) do
    res = response(Http.options(conn.url, params: [{"describe", "default"}]))
    res.body["response"]
  end

  def execute(conn, resource_path, action, opts) do
    r_desc = Enum.reduce(
      resource_path,
      conn.description,
      fn r, acc -> acc["resources"][r] end
    )

    a_desc = r_desc["actions"][action]

    Http.request(
      a_desc["method"],
      resolve_path_params(Path.join(conn.url, a_desc["url"]), conn.path_params),
      "",
      []
    )
    |> response()
  end

  defp response({:ok, response}) do
    %{response | body: Poison.decode!(response.body)}
  end

  defp resolve_path_params(path, []), do: check_path_params(path)

  defp resolve_path_params(path, params) when is_list(params) do
    Enum.reduce(
      params,
      path,
      fn param, acc ->
        Regex.replace(@path_param_rx, path, param, global: false)
      end
    ) |> check_path_params()
  end

  defp check_path_params(path) do
    if Regex.match?(@path_param_rx, path) do
      raise "unresolved path parameters in '#{path}'"

    else
      path
    end
  end
end
