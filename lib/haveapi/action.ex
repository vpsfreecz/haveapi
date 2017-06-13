defmodule HaveAPI.Action do
  defmacro __using__(_opts) do
    quote do
      @haveapi_method :get
      @haveapi_route ""
      @haveapi_desc ""
      @haveapi_aliases []
      @haveapi_parent_input []
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
          @haveapi_parent_input []
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
                Module.put_attribute(
                  __MODULE__,
                  :"haveapi_parent_#{v |> Atom.to_string |> String.downcase}",
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

  defmacro input([do: block]) do
    quote do
      parent_in = @haveapi_parent_input

      defmodule Input do
        use HaveAPI.Parameters.Dsl

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

  defmacro output([do: block]) do
    quote do
      parent_out = @haveapi_parent_output

      defmodule Output do
        use HaveAPI.Parameters.Dsl

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
    end
  end

  def execute(action, conn) do
    case apply(action, :exec, [%HaveAPI.Request{conn: conn, input: %{}}]) do
      response when is_map(response) ->
        Plug.Conn.send_resp(
          conn,
          200,
          HaveAPI.Protocol.send(true, response: response)
        )

      {:ok, response} when is_map(response) ->
        Plug.Conn.send_resp(
          conn,
          200,
          HaveAPI.Protocol.send(true, response: response)
        )

      {:error, msg} when is_binary(msg) ->
        Plug.Conn.send_resp(
          conn,
          400,
          HaveAPI.Protocol.send(false, message: msg)
        )

      _ ->
        Plug.Conn.send_resp(
          conn,
          500,
          HaveAPI.Protocol.send(false, message: "Server error occurred.")
        )
    end
  end
end
