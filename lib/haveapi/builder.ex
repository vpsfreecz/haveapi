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

      @haveapi_default_version nil
      Module.register_attribute __MODULE__, :haveapi_versions, accumulate: true
      @before_compile HaveAPI.Builder
    end
  end

  defmacro version(v, [do: block]) do
    mod = :"Version_#{v}"

    quote do
      @haveapi_versions unquote(mod)

      defmodule unquote(mod) do
        use HaveAPI.Version

        version unquote(v)
        unquote(block)
      end
    end
  end

  defmacro default(v) do
    quote do
      @haveapi_default_version unquote(v)
    end
  end

  defmacro mount(prefix \\ "/") do
    quote bind_quoted: [prefix: prefix] do
      ctx = %HaveAPI.Context{prefix: prefix}
      @haveapi_ctx ctx

      # Documentation of the whole API
      match prefix, via: :options do
        conn = binding()[:conn]
        def_v = default_version()

        Plug.Conn.send_resp(
          conn,
          200,
          HaveAPI.Protocol.send_doc(
            case conn.query_params["describe"] do
              "versions" ->
                %{
                  versions: Enum.map(versions(), &(&1.version)),
                  default: def_v.version,
                }

              "default" ->
                HaveAPI.Doc.version(%{@haveapi_ctx | version: def_v})

              _ -> # TODO: report error on invalid values?
                HaveAPI.Doc.api(@haveapi_ctx, @haveapi_versions, def_v)
            end
          )
        )
      end

      # Mount all versions
      Enum.each(@haveapi_versions, fn version ->
        # Per-version documentation
        @current_version version

        match Path.join([prefix, "v#{version.version}"]), via: :options do
          version = @current_version

          Plug.Conn.send_resp(
            binding()[:conn],
            200,
            HaveAPI.Protocol.send_doc(
              HaveAPI.Doc.version(
                %{@haveapi_ctx |
                  prefix: Path.join([@haveapi_ctx.prefix, "v#{version.version}"]),
                  version: version
                }
              )
            )
          )
        end

        Enum.each(version.resources, fn r ->
          Enum.each(r.actions, fn a ->
            @current_action %{ctx |
              prefix: Path.join([prefix, "v#{version.version}"]),
              version: version,
              resource: r,
              action: a
            }
            path = Path.join([@current_action.prefix, r.route, a.route])

            # Action execution
            match path, via: a.method do
              HaveAPI.Action.execute(@current_action, binding()[:conn])
            end

            # Action doc
            match Path.join([path, "method=#{a.method}"]), via: :options do
              Plug.Conn.send_resp(
                binding()[:conn],
                200,
                HaveAPI.Protocol.send_doc(HaveAPI.Doc.action(@current_action))
              )
            end
          end)
        end)
      end)

      # Mount the default version
      def_v = if @haveapi_default_version do
        Enum.find(@haveapi_versions, &(&1.version == @haveapi_default_version))

      else
        List.last(@haveapi_versions)
      end

      Enum.each(def_v.resources, fn r ->
        Enum.each(r.actions, fn a ->
          @current_action %{ctx |
            version: def_v,
            resource: r,
            action: a
          }
          path = Path.join([@current_action.prefix, r.route, a.route])

          # Action execution
          match path, via: a.method do
            HaveAPI.Action.execute(@current_action, binding()[:conn])
          end

          # Action doc
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
      def versions do
        Enum.reverse(@haveapi_versions)
      end

      def default_version do
        if @haveapi_default_version do
          Enum.find(@haveapi_versions, &(&1.version == @haveapi_default_version))

        else
          List.last(@haveapi_versions)
        end
      end

      def resources(version) do
        Enum.find(@haveapi_versions, &(&1.version == version)).resources
      end
    end
  end
end
