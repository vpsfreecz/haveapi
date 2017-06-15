defmodule HaveAPI.Version do
  defmacro __using__(_opts) do
    quote do
      @before_compile HaveAPI.Version
      @haveapi_version nil
      Module.register_attribute __MODULE__, :haveapi_resources, accumulate: true

      import HaveAPI.Version
    end
  end

  defmacro version(v) do
    quote do
      @haveapi_version unquote(v)
    end
  end

  defmacro resources(list) do
    quote do
      Enum.each(unquote(list), &(@haveapi_resources &1))
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def version, do: @haveapi_version
      def resources, do: @haveapi_resources
    end
  end
end
