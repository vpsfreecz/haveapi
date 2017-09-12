defmodule HaveAPI.Protocol do
  def describe_api(ctx, conn) do
    def_v = ctx.api.default_version

    Plug.Conn.send_resp(
      conn,
      200,
      format_doc(
        case conn.query_params["describe"] do
          "versions" ->
            %{
              versions: Enum.map(ctx.api.versions, &(&1.version)),
              default: def_v.version,
            }

          "default" ->
            HaveAPI.Doc.version(%{ctx | version: def_v})

          _ -> # TODO: report error on invalid values?
            HaveAPI.Doc.api(ctx, ctx.api.versions, def_v)
        end
      )
    )
  end

  def describe_version(ctx, conn) do
    Plug.Conn.send_resp(
      conn,
      200,
      format_doc(
        HaveAPI.Doc.version(%{ctx |
          user: HaveAPI.Authentication.user(conn)
        })
      )
    )
  end

  def describe_action(ctx, conn) do
    case HaveAPI.Doc.action(%{ctx | user: HaveAPI.Authentication.user(conn)}) do
      nil ->
        Plug.Conn.send_resp(
          conn,
          403,
          format_doc(nil, status: false, message: "Access forbidden")
        )

      doc ->
        Plug.Conn.send_resp(
          conn,
          200,
          format_doc(doc)
        )
    end
  end

  def send_data(%HaveAPI.Response{status: true} = res) do
    Plug.Conn.send_resp(
      res.conn,
      200,
      format_data(res.status, response: %{
        res.context.resource.name() => res.output,
      } |> add_meta(res))
    )
  end

  def send_data(%HaveAPI.Response{status: false} = res) do
    Plug.Conn.send_resp(
      res.conn,
      res.http_status || 400,
      format_data(res.status, message: res.message, errors: res.errors)
    )
  end

  def send_data(res) do
    Plug.Conn.send_resp(
      res.conn,
      res.http_status || 500,
      format_data(false, message: "Server error occurred.")
    )
  end

  def not_found(conn) do
    Plug.Conn.send_resp(var!(conn), 404, format_data(
      false,
      message: "Action not found"
    ))
  end

  def format_doc(doc, opts \\ []) do
    Poison.encode!(%{
      version: "1.2",
      status: Keyword.get(opts, :status, true),
      response: doc,
      message: Keyword.get(opts, :message, nil),
      errors: nil,
    })
  end

  def format_data(status, opts) do
    Poison.encode!(%{
      status: status,
      response: opts[:response] || nil,
      message: opts[:message] || nil,
      errors: opts[:errors] || nil,
    })
  end

  defp add_meta(data, %HaveAPI.Response{meta: nil}), do: data
  defp add_meta(data, %HaveAPI.Response{meta: meta}) do
    Map.put(data, HaveAPI.Meta.namespace, meta)
  end
end
