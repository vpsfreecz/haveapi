defmodule HaveAPI.Client.Protocol do
  alias HaveAPI.Client
  alias HaveAPI.Client.Http

  @path_param_rx ~r{:[^/]+}

  def describe(%Client.Conn{version: nil} = conn) do
    res = response(Http.options(conn.url, params: [{"describe", "default"}]))
    res.body["response"]
  end

  def describe(conn) do
    res = [conn.url, "v#{conn.version}"]
      |> Path.join
      |> Client.Conn.ensure_trailslash
      |> Http.options([])
      |> response

    res.body["response"]
  end

  def execute(conn, opts) do
    data = Http.request(
      conn.action_desc["method"],
      resolve_path_params(Path.join(conn.url, conn.action_desc["url"]), conn.path_params),
      "",
      []
    ) |> response()

    Client.Response.new(conn, data)
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
        Regex.replace(@path_param_rx, acc, to_string(param), global: false)
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
