defmodule HaveAPI.Parameters.Dsl do
  Enum.each(
    [:string, :text, :integer, :float, :datetime, :boolean],
    fn v ->
      def unquote(:"#{v}")(params, name, opts \\ []) do
        IO.puts("#{unquote(v)} #{name}")
        [name | params]
      end
    end
  )
end
