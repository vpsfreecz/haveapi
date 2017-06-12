defmodule HaveAPI.Action do
  defmacro __using__(_opts) do
    quote do
      @haveapi_method :get
      @haveapi_route ""
      @haveapi_desc ""
      @haveapi_aliases []
      @before_compile HaveAPI.Action

      import HaveAPI.Action
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
      defmodule Input do
        use HaveAPI.Parameters.Dsl

        unquote(block)
      end
    end
  end

  defmacro output([do: block]) do
    quote do
      defmodule Output do
        use HaveAPI.Parameters.Dsl

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
    apply(action, :exec, [conn])
  end
end
