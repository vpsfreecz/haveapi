defmodule HaveAPI.Builder do
  defmacro __using__(_opts) do
    quote do
      import HaveAPI.Builder
      use Plug.Router
      import Plug.Router, only: [match: 2, match: 3]

      plug :access_control, api: __MODULE__
      plug :cors
      plug :match
      plug :fetch_query_params
      plug Plug.Parsers,
        parsers: [:json],
        pass:  ["application/json"],
        json_decoder: Poison
      plug :dispatch

      @haveapi_prefix nil
      @haveapi_default_version nil
      Module.register_attribute __MODULE__, :haveapi_versions, accumulate: true
      @before_compile HaveAPI.Builder
    end
  end

  defmacro version(v, [do: block]) do
    quote do
      un_v = unquote(v)
      mod = :"#{__MODULE__}.Version_#{un_v}"

      @haveapi_versions mod

      defmodule :"#{mod}" do
        use HaveAPI.Version

        version un_v
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
      ctx = %HaveAPI.Context{api: __MODULE__, prefix: prefix}
      @haveapi_ctx ctx
      @haveapi_prefix prefix

      # Documentation of the whole API
      match prefix, via: :options do
        HaveAPI.Protocol.describe_api(@haveapi_ctx, var!(conn))
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
        :"#{__MODULE__}.Version_#{ctx.version.version}_Default_Router"
      else
        :"#{__MODULE__}.Version_#{ctx.version.version}_Router"
      end

      defmodule :"#{mod}" do
        use Plug.Router
        import HaveAPI.Authentication.Chain, only: [authenticate: 2]

        plug :match
        plug :authenticate, chain: ctx.version.auth_chain
        plug :dispatch

        # Per-version documentation
        @haveapi_ctx ctx

        match "/", via: :options do
          HaveAPI.Protocol.describe_version(@haveapi_ctx, var!(conn))
        end

        # Version auth
        Enum.each(ctx.version.auth_chain, fn auth ->
          Enum.each(
            auth.resources,
            &(mount_resource(%{ctx | prefix: "/_auth", resource_path: [&1], resource: &1}))
          )
        end)

        # Version actions
        Enum.each(ctx.version.resources, fn r ->
          mount_resource(%{ctx | prefix: "/", resource_path: [r], resource: r})
        end)

        # Default route
        match _ do
          HaveAPI.Protocol.not_found(var!(conn))
        end
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

  defmacro mount_resource(ctx) do
    quote bind_quoted: [ctx: ctx] do
      mount_single_resource(ctx)

      # Mount subresources
      Enum.each(ctx.resource.resources, fn r ->
        mount_single_resource(%{ctx | resource_path: ctx.resource_path ++ [r], resource: r})
      end)
    end
  end

  defmacro mount_single_resource(ctx) do
    quote bind_quoted: [ctx: ctx] do
      # Mount actions
      Enum.each(ctx.resource.actions, fn a ->
        @current_action %{ctx | action: a}

        path = Path.join(
          [ctx.prefix] ++
          Enum.map(ctx.resource_path, &(&1.route)) ++
          [a.route]
        ) |> a.resolve_route(ctx.resource_path)

        # Action execution
        match path, via: a.method do
          HaveAPI.Action.execute(@current_action, binding()[:conn])
        end

        # Action doc
        match Path.join([path, "method=#{a.method}"]), via: :options do
          HaveAPI.Protocol.describe_action(@current_action, var!(conn))
        end
      end)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def prefix, do: @haveapi_prefix

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

  def access_control(conn, [api: api]) do
    import Plug.Conn

    with [_] <- get_req_header(conn, "origin"),
         [_] <- get_req_header(conn, "access-control-request-method") do

      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "GET,POST,OPTIONS,PATCH,PUT,DELETE")
      |> put_resp_header("access-control-allow-credentials", "false")
      |> put_resp_header("access-control-allow-headers", allowed_headers(api))
      |> put_resp_header("access-control-max-age", to_string(60*60))
      |> send_resp(200, "")
      |> halt()

    else
      _ -> conn
    end
  end

  def cors(conn, _opts) do
    import Plug.Conn

    with [_] <- get_req_header(conn, "origin") do
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-credentials", "false")

    else
      _ -> conn
    end
  end

  defp allowed_headers(api) do
    for v <- api.versions do
      for auth <- v.auth_chain do
        auth.required_headers
      end
    end
    |> List.flatten()
    |> Enum.concat(["Content-Type"])
    |> Enum.join(",")
  end
end
