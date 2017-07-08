defmodule HaveAPI.Parameters do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use HaveAPI.Parameters.Dsl, only: opts[:only], except: opts[:except]
    end
  end

  @spec extract(nil | list(map), String.t, map) :: nil | map
  def extract(nil, _ns, _data), do: {:ok, nil}

  def extract(params, ns, data) do
    input = Map.get(data, ns, %{})

    {ret, errors} = Enum.reduce(
      params,
      {%{}, %{}},
      fn p, {ret, errors} ->
        case HaveAPI.Parameter.value(p, input) do
          {:ok, v} ->
            {Map.put(ret, p.name, v), errors}

          {:error, msg} ->
            {ret, Map.put(errors, p.name, [msg])}

          :not_present ->
            {ret, errors}
        end
      end
    )

    if Enum.empty?(errors) do
      {:ok, ret}

    else
      {:error, errors}
    end
  end

  def filter(ctx, out, data) do
    meta_ns = HaveAPI.Meta.namespace

    {ret, errors} = Enum.reduce(
      as_map(data),
      {%{}, %{}},
      fn
        {^meta_ns, params}, {acc, errors} ->
          filter_meta(acc, errors, ctx, :local, params)

        {k, v}, {acc, errors} ->
          format_param(acc, errors, ctx, Enum.find(out, &(&1.name == k)), v)
      end
    )

    if Enum.empty?(errors) do
      {:ok, ret}

    else
      {:error, errors}
    end
  end

  def layout_aware(data, func) when is_list(data) do
    Enum.map(data, func)
  end

  def layout_aware(data, func) when is_map(data) do
    func.(data)
  end

  def as_map(%{__struct__: _} = v), do: Map.from_struct(v)
  def as_map(v) when is_map(v), do: v

  def as_map_list(v) when is_list(v), do: Enum.map(v, &as_map/1)

  defp format_param(ret, errors, _ctx, nil, _value), do: {ret, errors}

  defp format_param(ret, errors, ctx, param, value) do
    case HaveAPI.Parameter.format(ctx, param, param.type, value) do
      {:ok, v} ->
        {Map.put(ret, param.name, v), errors}

      {:error, msg} ->
        {ret, Map.put(errors, param.name, [msg])}
    end
  end

  defp filter_meta(ret, errors, ctx, type, params) do
    if ctx.action.has_meta?(type) do
      do_filter_meta(ret, errors, ctx, type, params)

    else
      {ret, errors}
    end
  end

  defp do_filter_meta(ret, errors, ctx, type, params) do
    {meta, my_errors} = Enum.reduce(
      params,
      {%{}, %{}},
      fn {k, v}, {acc, errors} ->
        format_param(
          acc,
          errors,
          ctx,
          Enum.find(ctx.action.meta(type).params(:output), &(&1.name == k)),
          v
        )
      end
    )

    if Enum.empty?(my_errors) do
      if Enum.empty?(meta) do
        {ret, errors}

      else
        {Map.put(ret, HaveAPI.Meta.namespace, meta), errors}
      end

    else
      {ret, Map.put(errors, HaveAPI.Meta.namespace, my_errors)}
    end
  end
end
