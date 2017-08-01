defmodule HaveAPI.Action do
  alias HaveAPI.Action.Input
  alias HaveAPI.Action.Output

  defmacro __using__(_opts) do
    quote location: :keep do
      @haveapi_parent nil
      unquote(HaveAPI.Action.setup)

      defmacro __using__(_opts) do
        quote do
          parent = unquote(__MODULE__)

          @haveapi_parent parent
          unquote(HaveAPI.Action.setup)

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

          unquote(__MODULE__.use_template)
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

        Enum.each(
          parent_in,
          fn v -> @haveapi_params [v | @haveapi_params] end
        )

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

        Enum.each(
          parent_out,
          fn v -> @haveapi_params [v | @haveapi_params] end
        )

        unquote(block)
      end
    end
  end

  defmacro meta(:local, [do: block]) do
    quote do
      @haveapi_meta_local true
      parent = @haveapi_parent

      defmodule LocalMeta do
        use HaveAPI.Meta

        if parent && parent.has_meta?(:local) do
          Enum.each([:input, :output], fn dir ->
            attr = :"haveapi_parent_#{dir}"
            Module.register_attribute(__MODULE__, attr, [])

            params = parent.meta(:local).params(dir)

            if params do
              Module.put_attribute(__MODULE__, attr, params)
            end
          end)
        end

        unquote(block)
      end
    end
  end

  defmacro meta(:global, [do: block]) do
    quote do
      @haveapi_meta_global true
      parent = @haveapi_parent

      defmodule GlobalMeta do
        use HaveAPI.Meta

        if parent && parent.has_meta?(:global) do
          Enum.each([:input, :output], fn dir ->
            attr = :"haveapi_parent_#{dir}"
            Module.register_attribute(__MODULE__, :attr, [])

            params = parent.meta(:global).params(dir)

            if params do
              Module.put_attribute(__MODULE__, attr, params)
            end
          end)
        end

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

      parent = @haveapi_parent
      if parent do
        if parent.has_meta?(:local) && !@haveapi_meta_local do
          meta(:local) do
            if parent.meta(:local).params(:input) do
              input do: nil
            end

            if parent.meta(:local).params(:output) do
              output do: nil
            end
          end
        end

        if parent.has_meta?(:global) && !@haveapi_meta_global do
          meta(:global) do
            if parent.meta(:global).params(:input) do
              input do: nil
            end

            if parent.meta(:global).params(:output) do
              output do: nil
            end
          end
        end
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

      def template, do: @haveapi_parent
    end
  end

  def setup do
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

      def authorize(_req, _user), do: if auth(), do: :deny, else: :allow

      def use_template, do: nil

      defoverridable [authorize: 2, use_template: 0]
    end
  end

  def execute(ctx, conn) do
    ctx = %{ctx | conn: conn, user: HaveAPI.Authentication.user(conn)}
    req = %HaveAPI.Request{context: ctx, conn: conn, user: ctx.user}
    res = %HaveAPI.Response{context: ctx, conn: conn}

    with true <- authenticated?(ctx.action.auth, ctx.user),
         req <- Input.fetch_path_parameters(req),
         {:ok, req} <- Input.fetch_parameters(req),
         {:ok, req, params} <- HaveAPI.Authorization.authorize(req),
         :ok <- HaveAPI.Validator.validate(req, params),
         data <- do_exec(req),
         output = ctx.action.layout(:output),
         res <- Output.build(data, output, res),
         {:ok, res} <- HaveAPI.Authorization.authorize(res),
         {:ok, res} <- Output.filter(res, output),
         {:ok, res} <- Output.filter_meta(res) do
      reply(res)
    else
      {:error, msg} when is_binary(msg) ->
        reply(%{res | status: false, message: msg})

      {:error, msg, opts} when is_list(opts) ->
        reply(%{res | status: false, message: msg} |> Map.merge(Map.new(opts)))
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

    with {:ok, req, params} <- HaveAPI.Authorization.authorize(req),
         :ok <- HaveAPI.Validator.validate(req, params),
         data <- do_exec(req),
         res = %HaveAPI.Response{context: ctx, conn: conn},
         output = ctx.action.layout(:output),
         res <- Output.build(data, output, res),
         {:ok, res} <- HaveAPI.Authorization.authorize(res),
         {:ok, res} <- Output.filter(res, output),
    do: res
  end

  defp authenticated?(true, user) do
    if user, do: true, else: {:error, "Access forbidden", http_status: 403}
  end

  defp authenticated?(false, _user), do: true

  defp map_path_params(ctx, params) do
    route = Path.join(
      [ctx.prefix] ++
      Enum.map(ctx.resource_path, &(&1.route)) ++
      [ctx.action.route]
    ) |> ctx.action.resolve_route(ctx.resource_path)

    path_params = Regex.scan(~r{:([^/]+)}, route)
      |> Enum.map(fn [_m, v] -> String.to_atom(v) end)

    Enum.zip(path_params, params)
  end

  defp do_exec(req) do
    apply(req.context.action, :exec, [req])
  end

  defp reply(res), do: HaveAPI.Protocol.send_data(res)
end
