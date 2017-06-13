defmodule HaveAPI.Parameters.Dsl do
  defmacro __using__(opts) do
    quote do
      import HaveAPI.Parameters.Dsl

      Module.register_attribute __MODULE__, :haveapi_params, accumulate: true
      @haveapi_layout unquote(opts[:layout])
      @before_compile HaveAPI.Parameters.Dsl
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def layout do
        @haveapi_layout
      end

      def params do
        Enum.reverse(@haveapi_params)
      end
    end
  end

  Enum.each(
    [:string, :text, :integer, :float, :datetime, :boolean],
    fn v ->
      defmacro unquote(:"#{v}")(name, opts \\ []) do
        type = unquote(v)

        quote bind_quoted: [name: name, opts: opts, type: type] do
          @haveapi_params %HaveAPI.Parameter{
            name: name,
            type: type,
            label: opts[:label],
            description: opts[:description]
          }
        end
      end
    end
  )
end
