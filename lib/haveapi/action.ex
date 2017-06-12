defmodule HaveAPI.Action do
  defmacro __using__(_opts) do
    quote do
      @haveapi_method :get
      @haveapi_route ""
      @before_compile HaveAPI.Action

      import HaveAPI.Action
    end
  end

  defmacro method(v) do
    quote do
      @haveapi_method unquote(v)
    end
  end

  defmacro route(v) do
    quote do
      @haveapi_route unquote(v)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def method do
        @haveapi_method
      end

      def route do
        @haveapi_route
      end

      def name do
        Module.split(__MODULE__) |> List.last |> String.downcase
      end
    end
  end

  def execute(action, conn) do
    apply(action, :exec, [conn])
  end
end
