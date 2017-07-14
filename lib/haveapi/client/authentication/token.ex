defmodule HaveAPI.Client.Authentication.Token do
  alias HaveAPI.Client

  @behaviour Client.Authentication

  def setup(conn, opts) do
    if opts[:token] do
      {:ok, %{token: opts[:token], via: opts[:via] || :header}}

    else
      case request(token_conn(conn), opts) do
        {:ok, token, valid_to} ->
          {:ok, %{token: token, valid_to: valid_to, via: opts[:via] || :header}}

        {:error, msg} ->
          {:error, msg}
      end
    end
  end

  def authenticate(req, opts) do
    do_authenticate(req, opts[:via], opts[:token])
  end

  def request(conn, opts) do
    res = Client.call(conn, "request", input: %{
      login: opts[:username],
      password: opts[:password],
      lifetime: opts[:lifetime] || "renewable_auto",
      interval: opts[:interval] || 300
    })

    if Client.Response.ok?(res) do
      params = Client.Response.params(res)

      {:ok, params["token"], params["valid_to"]}

    else
      {:error, res.message}
    end
  end

  defp do_authenticate(req, :header, token) do
    Client.Request.add_header(req, desc(req.conn)["http_header"], token)
  end

  defp do_authenticate(req, :query_parameter, token) do
    Client.Request.add_query_param(req, desc(req.conn)["query_parameter"], token)
  end

  defp token_conn(conn) do
    %{conn |
      resource_path: ["token"],
      resource_desc: desc(conn)["resources"]["token"],
      path_params: []
    }
  end

  defp desc(conn) do
    conn.description["authentication"]["token"]
  end
end
