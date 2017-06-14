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
      @haveapi_resources %{}
      @before_compile HaveAPI.Builder
    end
  end

  defmacro resources(version, resource_list, opts \\ []) do
    quote bind_quoted: [version: version, resource_list: resource_list, opts: opts] do
      @haveapi_resources Map.put(@haveapi_resources, version, resource_list)

      if opts[:default] do
        @haveapi_default_version version
      end
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
                  versions: versions(),
                  default: def_v,
                }

              "default" ->
                HaveAPI.Doc.version(%{@haveapi_ctx | version: def_v}, @haveapi_resources[def_v])

              _ -> # TODO: report error on invalid values?
                HaveAPI.Doc.api(@haveapi_ctx, @haveapi_resources, def_v)
            end
          )
        )
      end

      # Mount all versions
      Enum.each(@haveapi_resources, fn {version, resource_list} ->
        # Per-version documentation
        @current_version {version, resource_list}

        match Path.join([prefix, "v#{version}"]), via: :options do
          {version, resource_list} = @current_version

          Plug.Conn.send_resp(
            binding()[:conn],
            200,
            HaveAPI.Protocol.send_doc(
              HaveAPI.Doc.version(
                %{@haveapi_ctx |
                  prefix: Path.join([@haveapi_ctx.prefix, "v#{version}"]),
                  version: version
                },
                resource_list
              )
            )
          )
        end

        Enum.each(resource_list, fn r ->
          Enum.each(r.actions, fn a ->
            @current_action %{ctx |
              prefix: Path.join([prefix, "v#{version}"]),
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
      def_v = @haveapi_default_version || (@haveapi_resources |> Map.keys |> List.first)

      Enum.each(
        @haveapi_resources[def_v],
        fn r ->
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
        Map.keys(@haveapi_resources)
      end

      def default_version do
        @haveapi_default_version || (@haveapi_resources |> Map.keys |> List.first)
      end

      def resources(version) do
        @haveapi_resources[version]
      end
    end
  end
end
