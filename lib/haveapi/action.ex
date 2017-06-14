defmodule HaveAPI.Action do
  defmacro __using__(_opts) do
    quote do
      @haveapi_method :get
      @haveapi_route ""
      @haveapi_desc ""
      @haveapi_aliases []
      @haveapi_parent_input_layout nil
      @haveapi_parent_input []
      @haveapi_parent_output_layout nil
      @haveapi_parent_output []
      @before_compile HaveAPI.Action

      import HaveAPI.Action

      defmacro __using__(_opts) do
        quote do
          parent = unquote(__MODULE__)

          @haveapi_method :get
          @haveapi_route ""
          @haveapi_desc ""
          @haveapi_aliases []
          @haveapi_parent_input_layout nil
          @haveapi_parent_input []
          @haveapi_parent_output_layout nil
          @haveapi_parent_output []
          @before_compile HaveAPI.Action

          Enum.each(
            [:method, :route, :aliases],
            fn v ->
              Module.put_attribute(
                __MODULE__,
                :"haveapi_#{v}",
                apply(parent, v, [])
              )
            end
          )

          Enum.each(
            [:Input, :Output],
            fn v ->
              mod = Module.concat(parent, v)

              if function_exported?(mod, :params, 0) do
                name = v |> Atom.to_string |> String.downcase

                Module.put_attribute(
                  __MODULE__,
                  :"haveapi_parent_#{name}_layout",
                  apply(mod, :layout, [])
                )
                Module.put_attribute(
                  __MODULE__,
                  :"haveapi_parent_#{name}",
                  apply(mod, :params, [])
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

  defmacro input(layout \\ nil, [do: block]) do
    quote do
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

  defmacro __before_compile__(_env) do
    quote do
      def method, do: @haveapi_method

      def route, do: @haveapi_route

      def name do
        Module.split(__MODULE__) |> List.last |> String.downcase
      end

      def desc, do: @haveapi_desc

      def aliases, do: @haveapi_aliases

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
    end
  end

  def execute(ctx, conn) do
    ret = %HaveAPI.Request{context: ctx, conn: conn}
      |> fetch_path_parameters
      |> fetch_input_parameters
      |> do_exec

    ret
      |> build_output(ctx.action.layout(:output), %HaveAPI.Response{context: ctx, conn: conn})
      |> filter_output(ctx.action.layout(:output))
      |> reply
  end

  defp fetch_path_parameters(req) do
    %{req | params: Enum.map(
      req.conn.path_params,
      fn {k,v} -> {String.to_atom(k), v} end
    )}
  end

  defp fetch_input_parameters(req) do
    Map.put(
      req,
      :input,
      if req.context.action.method == :get do
        HaveAPI.Parameters.extract(req.context, req.conn.query_params)

      else
        HaveAPI.Parameters.extract(req.context, req.conn.body_params)
      end
    )
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

  defp build_output({:error, msg}, :hash, res) when is_binary(msg) do
    %{res | status: false, message: msg}
  end

  defp build_output(data, :hash_list, res) when is_list(data) do
    %{res | status: true, output: data}
  end

  defp build_output({:ok, data}, :hash_list, res) when is_list(data) do
    %{res | status: true, output: data}
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
    %{res | output: HaveAPI.Parameters.filter(res.context, res.output)}
  end

  defp filter_output(res, :hash_list) do
    %{res | output: Enum.map(
      res.output,
      &(HaveAPI.Parameters.filter(res.context, &1))
    )}
  end

  defp reply(%HaveAPI.Response{status: true} = res) do
    Plug.Conn.send_resp(
      res.conn,
      200,
      HaveAPI.Protocol.send(true, response: %{res.context.resource.name() => res.output})
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
