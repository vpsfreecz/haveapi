defmodule HaveAPI.Resource do
  defmacro __using__(_opts) do
    quote do
      import HaveAPI.Resource
      @before_compile HaveAPI.Resource
      Module.register_attribute __MODULE__, :haveapi_actions, accumulate: true
    end
  end

  defmacro actions(acts) do
    quote do
      Enum.each(unquote(acts), &(@haveapi_actions &1))
    end
  end

  defmacro actions() do
    quote do
      @haveapi_actions
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def actions do
        @haveapi_actions
      end

      def route do
        name()
      end

      def name do
        Module.split(__MODULE__) |> List.last |> String.downcase
      end
    end
  end
end
