defmodule HaveAPI.Doc do
  def api(resources) do
    ctx = %HaveAPI.Context{version: 1}
    %{
      versions: %{1 => version(ctx, resources)},
      default: 1,
    }
  end

  def version(ctx, resources) do
    %{
      authentication: %{},
      resources: Enum.reduce(
        resources,
        %{},
        fn r, acc -> Map.put(acc, r.name, resource(%{ctx | resource: r})) end
      ),
      meta: %{namespace: "meta"}
    }
  end

  def resource(ctx) do
    %{
      actions: Enum.reduce(
        ctx.resource.actions,
        %{},
        fn a, acc -> Map.put(acc, a.name, action(%{ctx | action: a})) end
      ),
      resources: %{},
    }
  end

  def action(ctx) do
    method = ctx.action.method |> Atom.to_string |> String.upcase

    %{
      auth: false, # TODO
      description: ctx.action.desc,
      aliases: ctx.action.aliases,
      blocking: false, # TODO
      input: io(ctx, :Input),
      output: io(ctx, :Output),
      examples: [], # TODO
      meta: nil, # TODO
      url: ctx.action.route,
      method: method,
      help: "#{ctx.action.route}?method=#{method}"
    }
  end

  def io(ctx, dir) do
    mod = Module.concat(ctx.action, dir)

    v = apply(mod, :params, [])

    if Enum.empty?(v) do
      nil

    else
      %{
        layout: :hash,
        namespace: ctx.resource.name(),
        parameters: params(ctx, v),
      }
    end

  rescue
    UndefinedFunctionError -> nil
  end

  def params(ctx, param_list) do
    Enum.reduce(
      param_list,
      %{},
      fn p, acc -> Map.put(acc, p.name, param(p)) end
    )
  end

  def param(p) do
    %{
      label: p.label,
      description: p.description,
      type: p.type |> Atom.to_string |> String.capitalize,
      default: p.default,
    }
  end
end
