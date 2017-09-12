defmodule HaveAPI.Resource do
  defmacro __using__(_opts) do
    quote do
      import HaveAPI.Resource
      @before_compile HaveAPI.Resource
      Module.register_attribute __MODULE__, :haveapi_actions, accumulate: true
      Module.register_attribute __MODULE__, :haveapi_resources, accumulate: true
      @haveapi_route nil
    end
  end

  defmacro resource_route(v) do
    quote do: @haveapi_route unquote(v)
  end

  defmacro resources(list) do
    quote do
      Enum.each(unquote(list), &(@haveapi_resources &1))
    end
  end

  defmacro actions(acts) do
    quote do
      Enum.each(unquote(acts), &(@haveapi_actions &1))
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def resources do
        @haveapi_resources
      end

      def actions do
        @haveapi_actions
      end

      def route do
        _route() || name()
      end

      def name do
        Module.split(__MODULE__) |> List.last |> String.downcase
      end

      defp _route, do: @haveapi_route
    end
  end
end
