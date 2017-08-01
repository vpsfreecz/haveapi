defmodule HaveAPI.Parameter do
  defstruct [
    :name,
    :label,
    :description,
    :type,
    :default,
    :fill,
    :validators,
    :resource_path,
    :value_id,
    :value_label,
  ]

  @spec value(map, map) :: {:ok, any} | {:error, String.t} | :not_present
  def value(p, data) do
    name = Atom.to_string(p.name)
    value = if Map.has_key?(data, name) do
      {:ok, data[name]}

    else
      default_value(p.default, p.fill)
    end

    case value do
      {:ok, v} ->
        HaveAPI.Parameter.Input.coerce(p.type, v)

      other ->
        other
    end
  end

  def format(ctx, p, :resource, nil), do: {:ok, nil}

  def format(ctx, p, :resource, value) do
    assoc = List.last(p.resource_path)
    show = Enum.find(assoc.actions, &(&1.name == "show"))

    ret = HaveAPI.Action.internal(
      %{ctx |
        resource_path: p.resource_path,
        resource: assoc,
        action: show,
      },
      params: value
    )

    case ret do
      {:error, msg} ->
        {:error, msg}

      {:error, msg, _opts} ->
        {:error, msg}

      _ ->
        if ret.output do
          {:ok, HaveAPI.Meta.add(ret.output, %{
            resolved: true,
            url_params: value,
          })}
        else
          raise "#{ctx.action} returned #{p.name}=#{inspect(value)}, but #{show} returned nil"
        end
    end
  end

  def format(_ctx, p, _, value) do
    HaveAPI.Parameter.Output.coerce(p.type, value)
  end

  defp default_value(:_none, _fill), do: :not_present
  defp default_value(value, true), do: {:ok, value}
  defp default_value(_value, _fill), do: :not_present
end
