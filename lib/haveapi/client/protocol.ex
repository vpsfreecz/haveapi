defmodule HaveAPI.Client.Protocol do
  alias HaveAPI.Client
  alias HaveAPI.Client.Http

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

  def execute(req) do
    data = Http.request(
      req.conn.action_desc["method"],
      Path.join([req.conn.url, req.path]),
      request_body(req.body),
      req.headers,
      params: req.query_params
    ) |> response()

    Client.Response.new(req.conn, data)
  end

  defp request_body(""), do: ""
  defp request_body(body), do: Poison.encode!(body)

  defp response({:ok, response}) do
    %{response | body: Poison.decode!(response.body)}
  end
end
