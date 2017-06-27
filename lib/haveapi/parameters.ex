defmodule HaveAPI.Parameters do
  defmacro __using__(opts) do
    quote do
      use HaveAPI.Parameters.Dsl, only: opts[:only], except: opts[:except]
    end
  end

  def extract(nil, _ns, _data), do: nil

  def extract(_params, _ns, data) when map_size(data) == 0 do
    nil
  end

  def extract(params, ns, data) do
    if data[ns] do
      Enum.filter_map(
        data[ns],
        fn {k, v} ->
          Enum.find(params, &(k == Atom.to_string(&1.name)))
        end,
        fn {k, v} ->
          {String.to_atom(k), v}
        end
      ) |> Map.new

    else
      nil
    end
  end

  def filter(ctx, out, data) do
    meta_ns = HaveAPI.Meta.namespace

    Enum.reduce(
      data,
      %{},
      fn
        {^meta_ns, params}, acc -> filter_meta(acc, ctx, :local, params)
        {k, v}, acc ->
          format_param(acc, ctx, Enum.find(out, &(&1.name == k)), v)
      end
    )
  end

  def layout_aware(data, func) when is_list(data) do
    Enum.map(data, func)
  end

  def layout_aware(data, func) when is_map(data) do
    func.(data)
  end

  defp format_param(ret, _ctx, nil, _value), do: ret

  defp format_param(ret, ctx, param, value) do
    Map.put(
      ret,
      param.name,
      HaveAPI.Parameter.format(ctx, param, param.type, value)
    )
  end

  defp filter_meta(ret, ctx, type, params) do
    if ctx.action.has_meta?(type) do
      meta = Enum.reduce(
        params,
        %{},
        fn {k, v}, acc ->
          format_param(
            acc,
            ctx,
            Enum.find(ctx.action.meta(type).params(:output), &(&1.name == k)),
            v
          )
        end
      )

      if Enum.empty?(meta) do
        ret

      else
        Map.put(ret, HaveAPI.Meta.namespace, meta)
      end

    else
      ret
    end
  end
end
