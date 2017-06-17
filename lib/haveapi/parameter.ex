defmodule HaveAPI.Parameter do
  defstruct [
    :name,
    :label,
    :description,
    :type,
    :default,
    :resource_path,
    :value_id,
    :value_label,
  ]

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

    ret.output
  end

  def format(ctx, p, _, value) do
    value
  end
end
