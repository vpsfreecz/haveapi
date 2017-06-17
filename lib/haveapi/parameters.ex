defmodule HaveAPI.Parameters do
  defmacro __using__(opts) do
    quote do
      use HaveAPI.Parameters.Dsl, only: opts[:only], except: opts[:except]
    end
  end

  def extract(ctx, data) when map_size(data) == 0 do
    nil
  end

  def extract(ctx, data) do
    if data[ctx.resource.name] do
      allowed = ctx.action.params(:input)

      Enum.filter_map(
        data[ctx.resource.name],
        fn {k, v} ->
          Enum.find(allowed, &(k == Atom.to_string(&1.name)))
        end,
        fn {k, v} ->
          {String.to_atom(k), v}
        end
      ) |> Map.new

    else
      nil
    end
  end

  def filter(ctx, data) do
    data
      |> Enum.filter_map(
           fn {k, v} ->
             Enum.find(ctx.action.params(:output), &(k == &1.name))
           end,
           fn {k, v} ->
             p = Enum.find(ctx.action.params(:output), &(k == &1.name))
             {k, HaveAPI.Parameter.format(ctx, p, p.type, v)}
           end
        )
      |> Map.new
  end
end
