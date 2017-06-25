defmodule HaveAPI.Protocol do
  def read() do

  end

  def send(status, opts) do
    Poison.encode!(%{
      status: status,
      response: opts[:response] || nil,
      message: opts[:message] || nil,
      errors: opts[:errors] || nil,
    })
  end

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
    Plug.Conn.send_resp(
      conn,
      200,
      format_doc(HaveAPI.Doc.action(%{ctx |
        user: HaveAPI.Authentication.user(conn)
      }))
    )
  end

  def format_doc(doc) do
    Poison.encode!(%{
      version: "1.2",
      status: true,
      response: doc,
      message: nil,
      errors: nil,
    })
  end
end
