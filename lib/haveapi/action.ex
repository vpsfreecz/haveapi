defmodule HaveAPI.Action do
  defmacro __using__(_opts) do
    quote do
      @haveapi_method :get
      @haveapi_route ""
      @haveapi_desc ""
      @haveapi_aliases []
      @haveapi_auth true
      @haveapi_input false
      @haveapi_parent_input_layout nil
      @haveapi_parent_input []
      @haveapi_output false
      @haveapi_parent_output_layout nil
      @haveapi_parent_output []
      @haveapi_meta_local false
      @haveapi_meta_global false
      @before_compile HaveAPI.Action

      import HaveAPI.Action

      defmacro __using__(_opts) do
        quote do
          parent = unquote(__MODULE__)

          @haveapi_method :get
          @haveapi_route ""
          @haveapi_desc ""
          @haveapi_aliases []
          @haveapi_auth true
          @haveapi_input false
          @haveapi_parent_input_layout nil
          @haveapi_parent_input []
          @haveapi_output false
          @haveapi_parent_output_layout nil
          @haveapi_parent_output []
          @haveapi_meta_local false
          @haveapi_meta_global false
          @before_compile HaveAPI.Action

          Enum.each(
            [:method, :route, :aliases, :auth],
            fn v ->
              Module.put_attribute(
                __MODULE__,
                :"haveapi_#{v}",
                apply(parent, v, [])
              )
            end
          )

          Enum.each(
            [:input, :output],
            fn dir ->
              params = parent.params(dir)

              if params do
                Module.put_attribute(
                  __MODULE__,
                  :"haveapi_parent_#{dir}_layout",
                  parent.layout(dir)
                )
                Module.put_attribute(
                  __MODULE__,
                  :"haveapi_parent_#{dir}",
                  params
                )
              end
            end
          )

          import HaveAPI.Action
        end
      end
    end
  end

  defmacro method(v) do
    quote do: @haveapi_method unquote(v)
  end

  defmacro route(v) do
    quote do: @haveapi_route unquote(v)
  end

  defmacro desc(v) do
    quote do: @haveapi_desc unquote(v)
  end

  defmacro aliases(v) do
    quote do: @haveapi_aliases (@haveapi_aliases ++ unquote(v))
  end

  defmacro auth(v) when is_boolean(v) do
    quote do: @haveapi_auth unquote(v)
  end

  defmacro input(layout \\ nil, [do: block]) do
    quote do
      @haveapi_input true

      layout = case unquote(layout) do
        nil ->
          @haveapi_parent_input_layout || :hash

        any ->
          any
      end

      parent_in = @haveapi_parent_input

      defmodule Input do
        use HaveAPI.Parameters.Dsl, layout: layout

        unless Enum.empty?(parent_in) do
          Enum.each(
            parent_in,
            fn v -> @haveapi_params v end
          )
        end

        unquote(block)
      end
    end
  end

  defmacro output(layout \\ nil, [do: block]) do
    quote do
      @haveapi_output true

      layout = case unquote(layout) do
        nil ->
          @haveapi_parent_output_layout || :hash

        any ->
          any
      end

      parent_out = @haveapi_parent_output

      defmodule Output do
        use HaveAPI.Parameters.Dsl, layout: layout

        unless Enum.empty?(parent_out) do
          Enum.each(
            parent_out,
            fn v -> @haveapi_params v end
          )
        end

        unquote(block)
      end
    end
  end

  defmacro meta(:local, [do: block]) do
    quote do
      @haveapi_meta_local true

      defmodule LocalMeta do
        use HaveAPI.Meta

        unquote(block)
      end
    end
  end

  defmacro meta(:global, [do: block]) do
    quote do
      @haveapi_meta_global true

      defmodule GlobalMeta do
        use HaveAPI.Meta

        unquote(block)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      if @haveapi_parent_input_layout && !@haveapi_input do
        input do: nil
      end

      if @haveapi_parent_output_layout && !@haveapi_output do
        output do: nil
      end

      def method, do: @haveapi_method

      def route, do: @haveapi_route

      def resolve_route(route, [resource]) do
        route = Regex.replace(~r/%{resource}/, route, resource.name, global: true)
        route = Regex.replace(~r/%{action}/, route, name(), global: true)
      end

      def resolve_route(route, [first, second]) do
        route = Regex.replace(~r/%{resource}/, route, first.name, global: false)
        route = Regex.replace(~r/%{resource}/, route, second.name, global: true)
        route = Regex.replace(~r/%{action}/, route, name(), global: true)
      end

      def name do
        Module.split(__MODULE__) |> List.last |> String.downcase
      end

      def desc, do: @haveapi_desc

      def aliases, do: @haveapi_aliases

      def auth, do: @haveapi_auth

      def io(:input) do
        Module.concat(__MODULE__, :Input)
      end

      def io(:output) do
        Module.concat(__MODULE__, :Output)
      end

      def layout(dir) do
        apply(io(dir), :layout, [])

      rescue
        UndefinedFunctionError -> nil
      end

      def params(dir) do
        apply(io(dir), :params, [])

      rescue
        UndefinedFunctionError -> nil
      end

      def has_meta?(:local), do: @haveapi_meta_local
      def has_meta?(:global), do: @haveapi_meta_global

      def meta(:local), do: Module.concat(__MODULE__, :LocalMeta)
      def meta(:global), do: Module.concat(__MODULE__, :GlobalMeta)

      def authorize(_req, _user), do: if auth(), do: :deny, else: :allow

      defoverridable [authorize: 2]
    end
  end

  def execute(ctx, conn) do
    ctx = %{ctx | conn: conn, user: conn.private.haveapi_user}
    req = %HaveAPI.Request{context: ctx, conn: conn, user: ctx.user}
    res = %HaveAPI.Response{context: ctx, conn: conn}

    with true <- authenticated?(ctx.action.auth, ctx.user),
         req <- fetch_path_parameters(req),
         req <- fetch_input_parameters(req),
         {:ok, req} <- HaveAPI.Authorization.authorize(req),
         data <- do_exec(req),
         output = ctx.action.layout(:output),
         res <- build_output(data, output, res),
         {:ok, res} <- HaveAPI.Authorization.authorize(res),
         res <- filter_output(res, output),
         res <- filter_output_meta(res) do
      reply(res)
    else
      {:error, msg} -> reply(%{res | status: false, message: msg})
    end
  end

  def internal(%HaveAPI.Context{conn: conn} = ctx, opts \\ []) do
    req = %HaveAPI.Request{
      context: ctx,
      conn: conn,
      user: ctx.user,
      params: opts[:params] && map_path_params(ctx, opts[:params]),
      input: opts[:input],
    }

    with {:ok, req} <- HaveAPI.Authorization.authorize(req),
         data <- do_exec(req),
         res = %HaveAPI.Response{context: ctx, conn: conn},
         output = ctx.action.layout(:output),
         res <- build_output(data, output, res),
         {:ok, res} <- HaveAPI.Authorization.authorize(res),
         res <- filter_output(res, output),
    do: res
  end

  defp authenticated?(true, user) do
    if user, do: true, else: {:error, "Access forbidden"}
  end

  defp authenticated?(false, _user), do: true

  defp map_path_params(ctx, params) do
    route = Path.join(
      [ctx.prefix] ++
      Enum.map(ctx.resource_path, &(&1.route)) ++
      [ctx.action.route]
    ) |> ctx.action.resolve_route(ctx.resource_path)

    path_params = Regex.scan(~r{:([^/]+)}, route)
      |> Enum.map(fn [m, v] -> String.to_atom(v) end)

    Enum.zip(path_params, params)
  end

  defp fetch_path_parameters(req) do
    %{req | params: Enum.map(
      req.conn.path_params,
      fn {k,v} -> {String.to_atom(k), v} end
    )}
  end

  defp fetch_input_parameters(req) do
    if req.context.action.method == :get do
      fetch_input_parameters(req, req.conn.query_params)

    else
      fetch_input_parameters(req, req.conn.body_params)
    end
  end

  defp fetch_input_parameters(req, data) do
    %{req |
      input: fetch_input_parameters(req, data, :input),
      meta: fetch_input_parameters(req, data, :meta),
    }
  end

  defp fetch_input_parameters(req, data, :input) do
    HaveAPI.Parameters.extract(
      req.context.action.params(:input),
      req.context.resource.name,
      data
    )
  end

  defp fetch_input_parameters(req, data, :meta) do
    if req.context.action.has_meta?(:global) do
      HaveAPI.Parameters.extract(
        req.context.action.meta(:global).params(:input),
        Atom.to_string(HaveAPI.Meta.namespace),
        data
      )
    end
  end

  defp do_exec(req) do
    apply(req.context.action, :exec, [req])
  end

  defp build_output(:ok, nil, res) do
    %{res | status: true}
  end

  defp build_output({:error, msg}, nil, res) when is_binary(msg) do
    %{res | status: false, message: msg}
  end

  defp build_output(data, :hash, res) when is_map(data) do
    %{res | status: true, output: data}
  end

  defp build_output({:ok, data}, :hash, res) when is_map(data) do
    %{res | status: true, output: data}
  end

  defp build_output({:ok, data, meta}, :hash, res) when is_map(meta) do
    %{res | status: true, output: data, meta: meta}
  end

  defp build_output({:error, msg}, :hash, res) when is_binary(msg) do
    %{res | status: false, message: msg}
  end

  defp build_output(data, :hash_list, res) when is_list(data) do
    %{res | status: true, output: data}
  end

  defp build_output({:ok, data}, :hash_list, res) when is_list(data) do
    %{res | status: true, output: data}
  end

  defp build_output({:ok, data, meta}, :hash_list, res) when is_map(meta) do
    %{res | status: true, output: data, meta: meta}
  end

  defp build_output({:error, msg}, :hash_list, res) when is_binary(msg) do
    %{res | status: false, message: msg}
  end

  defp build_output(_, _, res) do
    %{res | status: false, message: "Server error occurred."}
  end

  defp filter_output(%HaveAPI.Response{output: nil} = res, _) do
    res
  end

  defp filter_output(res, :hash) do
    %{res |
      output: HaveAPI.Parameters.filter(
        res.context,
        res.context.action.params(:output),
        res.output
      )
    }
  end

  defp filter_output(res, :hash_list) do
    %{res | output: Enum.map(
      res.output,
      &(HaveAPI.Parameters.filter(res.context, res.context.action.params(:output), &1))
    )}
  end

  defp filter_output_meta(res) do
    if res.context.action.has_meta?(:global) && res.meta do
      params = res.context.action.meta(:global).params(:output)

      if params do
        %{res | meta: HaveAPI.Parameters.filter(res.context, params, res.meta)}

      else
        %{res | meta: nil}
      end

    else
      res
    end
  end

  defp reply(%HaveAPI.Response{status: true} = res) do
    Plug.Conn.send_resp(
      res.conn,
      200,
      HaveAPI.Protocol.send(true, response: %{
        res.context.resource.name() => res.output,
        HaveAPI.Meta.namespace => res.meta,
      })
    )
  end

  defp reply(%HaveAPI.Response{status: false} = res) do
    Plug.Conn.send_resp(
      res.conn,
      400,
      HaveAPI.Protocol.send(false, message: res.message)
    )
  end

  defp reply(res) do
    Plug.Conn.send_resp(
      res.conn,
      500,
      HaveAPI.Protocol.send(false, message: "Server error occurred.")
    )
  end
end
