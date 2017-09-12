defmodule HaveAPI.Meta do
  defmacro __using__(_opts) do
    quote do
      @haveapi_parent_input_layout nil
      @haveapi_parent_input []
      @haveapi_parent_output_layout nil
      @haveapi_parent_output []
      @before_compile HaveAPI.Meta
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def io(:input) do
        Module.concat(__MODULE__, :Input)
      end

      def io(:output) do
        Module.concat(__MODULE__, :Output)
      end

      def params(dir) do
        apply(io(dir), :params, [])

      rescue
        UndefinedFunctionError -> nil
      end
    end
  end

  def namespace, do: :_meta

  def add(data, meta) do
    Map.put(data, namespace(), meta)
  end
end
