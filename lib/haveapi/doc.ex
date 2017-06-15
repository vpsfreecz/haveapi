defmodule HaveAPI.Doc do
  def api(ctx, versions, default_v) do
    %{
      versions: Enum.reduce(
        versions,
        %{},
        fn v, acc ->
          Map.put(
            acc,
            v.version,
            version(%{ctx | prefix: Path.join([ctx.prefix, "v#{v.version}"]), version: v})
          )
        end
      ),
      default: version(%{ctx | version: default_v}),
    }
  end

  def version(ctx) do
    %{
      authentication: %{},
      resources: Enum.reduce(
        ctx.version.resources,
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
    route = Path.join([ctx.prefix, ctx.resource.name, ctx.action.route])

    %{
      auth: false, # TODO
      description: ctx.action.desc,
      aliases: ctx.action.aliases,
      blocking: false, # TODO
      input: io(ctx, :input),
      output: io(ctx, :output),
      examples: [], # TODO
      meta: nil, # TODO
      url: route,
      method: method,
      help: Path.join([route, "method=#{ctx.action.method}"]),
    }
  end

  def io(ctx, dir) do
    v = ctx.action.params(dir)

    if is_nil(v) || Enum.empty?(v) do
      nil

    else
      %{
        layout: apply(ctx.action.io(dir), :layout, []),
        namespace: ctx.resource.name(),
        parameters: params(ctx, v),
      }
    end
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
