defmodule HaveAPI.Client.Request do
  alias HaveAPI.Client

  @enforce_keys [:conn]
  defstruct [:conn, :path, :headers, :query_params, :body]

  @path_param_rx ~r{:[^/]+}

  def new(conn) do
    %__MODULE__{
      conn: conn,
      path: conn.action_desc["url"],
      headers: [],
      query_params: [],
      body: %{}
    }
  end

  def add_header(req, name, value) do
    %{req | headers: [{to_string(name), to_string(value)} | req.headers]}
  end

  def add_input(req, nil), do: req
  def add_input(req, params) when is_map(params) and map_size(params) == 0, do: req

  def add_input(req, params) when is_map(params) and map_size(params) > 0 do
    if req.conn.action_desc["input"] do
      do_add_params(
        req,
        req.conn.action_desc["method"],
        req.conn.action_desc["input"]["namespace"],
        params
      )

    else
      raise "action #{Enum.join(req.conn.resource_path, ".")}##{req.conn.action_name}} " <>
            "does not accept input parameters"
    end
  end

  def add_meta(req, nil), do: req
  def add_meta(req, params) when is_map(params) and map_size(params) == 0, do: req

  def add_meta(req, params) when is_map(params) and map_size(params) > 0 do
    if req.conn.action_desc["meta"]["global"]["input"] do
      do_add_params(
        req,
        req.conn.action_desc["method"],
        req.conn.description["meta"]["namespace"],
        params
      )

    else
      raise "action #{Enum.join(req.conn.resource_path, ".")}##{req.conn.action_name}} " <>
            "does not accept meta input parameters"
    end
  end

  def finalize(req) do
    %{req | headers: Enum.reverse(req.headers)}
  end

  def execute(conn, opts) do
    conn
    |> new()
    |> resolve_path_params(conn.path_params)
    |> check_path_params()
    |> add_input(opts[:input])
    |> add_meta(opts[:meta])
    |> Client.Authentication.authenticate()
    |> finalize()
    |> Client.Protocol.execute()
  end

  defp resolve_path_params(req, []), do: req

  defp resolve_path_params(req, params) when is_list(params) do
    %{req | path: Enum.reduce(
        params,
        req.path,
        fn param, acc ->
          Regex.replace(@path_param_rx, acc, to_string(param), global: false)
        end
    )}
  end

  defp check_path_params(req) do
    if Regex.match?(@path_param_rx, req.path) do
      raise "unresolved path parameters in '#{req.path}'"
    end

    req
  end

  defp do_add_params(req, "GET", ns, params) do
    %{req | query_params: req.query_params ++ Enum.map(
      params,
      fn {k,v} -> {"#{ns}[#{k}]", query_param(v)} end
    )}
  end

  defp do_add_params(req, _method, ns, params) do
    put_in(req.body, %{ns => params})
  end

  defp query_param(true), do: "1"
  defp query_param(false), do: "0"
  defp query_param(v) when is_binary(v), do: v
  defp query_param(v), do: to_string(v)
end
