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

  @spec value(map, map) :: {:ok, any} | :not_present
  def value(p, data) do
    name = Atom.to_string(p.name)

    if Map.has_key?(data, name) do
      {:ok, data[name]}

    else
      default_value(p.default, p.fill)
    end
  end

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
        nil
      _ ->
        HaveAPI.Meta.add(ret.output, %{
          resolved: true,
          url_params: value,
        })
    end
  end

  def format(ctx, p, _, value) do
    value
  end

  defp default_value(:_none, _fill), do: :not_present
  defp default_value(value, true), do: {:ok, value}
  defp default_value(value, _fill), do: :not_present
end
