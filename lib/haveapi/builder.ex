defmodule HaveAPI.Builder do
  defmacro __using__(_opts) do
    quote do
      import HaveAPI.Builder
      use Plug.Router

      plug :match
      plug :fetch_query_params
      plug Plug.Parsers,
        parsers: [:json],
        pass:  ["application/json"],
        json_decoder: Poison
      plug :dispatch

      Module.register_attribute __MODULE__, :haveapi_resources, accumulate: true
      @before_compile HaveAPI.Builder
    end
  end

  defmacro resources(res) do
    quote do
      Enum.each(unquote(res), &(@haveapi_resources &1))
    end
  end

  defmacro resources() do
    quote do
      @haveapi_resources
    end
  end

  defmacro mount(prefix \\ "/") do
    quote bind_quoted: [prefix: prefix] do
      ctx = %HaveAPI.Context{prefix: prefix, version: 1}
      @haveapi_ctx ctx

      match prefix, via: :options do
        conn = binding()[:conn]

        Plug.Conn.send_resp(
          conn,
          200,
          HaveAPI.Protocol.send_doc(
            case conn.query_params["describe"] do
              "versions" ->
                %{
                  versions: [1],
                  default: 1,
                }

              "default" ->
                HaveAPI.Doc.version(@haveapi_ctx, @haveapi_resources)

              _ -> # TODO: report error on invalid values?
                HaveAPI.Doc.api(@haveapi_ctx, @haveapi_resources)
            end
          )
        )
      end

      Enum.each(@haveapi_resources, fn r ->
        Enum.each(r.actions, fn a ->
          @current_action %{ctx | resource: r, action: a}
          path = Path.join([prefix, r.route, a.route])

          match path, via: a.method do
            HaveAPI.Action.execute(@current_action, binding()[:conn])
          end

          match Path.join([path, "method=#{a.method}"]), via: :options do
            Plug.Conn.send_resp(
              binding()[:conn],
              200,
              HaveAPI.Protocol.send_doc(HaveAPI.Doc.action(@current_action))
            )
          end
        end)
      end)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def router do
        HaveAPI.Builder
      end
    end
  end
end
