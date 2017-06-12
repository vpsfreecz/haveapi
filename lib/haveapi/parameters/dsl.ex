defmodule HaveAPI.Parameters.Dsl do
  defmacro __using__(_opts) do
    quote do
      import HaveAPI.Parameters.Dsl

      Module.register_attribute __MODULE__, :haveapi_params, accumulate: true
      @before_compile HaveAPI.Parameters.Dsl
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def params do
        @haveapi_params
      end
    end
  end

  Enum.each(
    [:string, :text, :integer, :float, :datetime, :boolean],
    fn v ->
      defmacro unquote(:"#{v}")(name, opts \\ []) do
        IO.puts("#{unquote(v)} #{name}")

        quote do
          @haveapi_params unquote(name)
        end
      end
    end
  )
end
