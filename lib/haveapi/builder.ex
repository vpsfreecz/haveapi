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

      # Setup Plug.Router per API version
      Enum.each(@haveapi_versions, fn version ->
        mount_version(%{ctx |
          prefix: Path.join([@haveapi_ctx.prefix, "v#{version.version}"]),
          version: version
        })
      end)

      # Setup the default API version
      def_v = if @haveapi_default_version do
        Enum.find(@haveapi_versions, &(&1.version == @haveapi_default_version))

      else
        List.last(@haveapi_versions)
      end

      mount_version(%{ctx | version: def_v}, true)
    end
  end

  defmacro mount_version(ctx, default \\ false) do
    quote bind_quoted: [ctx: ctx, default: default] do
      mod = if default do
        :"Version_#{ctx.version.version}_Default_Router"
      else
        :"Version_#{ctx.version.version}_Router"
      end

      defmodule :"#{mod}" do
        use Plug.Router

        plug :match
        plug :dispatch

        # Per-version documentation
        @haveapi_ctx ctx

        match "/", via: :options do
          version = @haveapi_ctx.version

          Plug.Conn.send_resp(
            binding()[:conn],
            200,
            HaveAPI.Protocol.send_doc(
              HaveAPI.Doc.version(%{@haveapi_ctx | version: version})
            )
          )
        end

        # Version actions
        Enum.each(ctx.version.resources, fn r ->
          Enum.each(r.actions, fn a ->
            @current_action %{ctx |
              resource: r,
              action: a
            }
            path = Path.join(["/", r.route, a.route])

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

      # Forward to version router
      @haveapi_forward_target mod
      @haveapi_forward_opts @haveapi_forward_target.init([])

      path = if default do
        ""
      else
        ctx.prefix
      end

      match(Path.join([path | ["*glob"]])) do
        Plug.Router.Utils.forward(
          var!(conn),
          var!(glob),
          @haveapi_forward_target,
          @haveapi_forward_opts
        )
      end
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
