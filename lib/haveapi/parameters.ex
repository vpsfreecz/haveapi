defmodule HaveAPI.Parameters do
  defmacro __using__(opts) do
    quote do
      use HaveAPI.Parameters.Dsl, only: opts[:only], except: opts[:except]
    end
  end

  @spec extract(nil | list(map), String.t, map) :: nil | map
  def extract(nil, _ns, _data), do: nil

  def extract(params, ns, data) do
    input = Map.get(data, ns, %{})

    Enum.reduce(
      params,
      %{},
      fn p, acc ->
        case HaveAPI.Parameter.value(p, input) do
          {:ok, v} ->
            Map.put(acc, p.name, v)

          :not_present ->
            acc
        end
      end
    )
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
