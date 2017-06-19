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
      authentication: Enum.reduce(
        ctx.version.auth_chain,
        %{},
        fn auth, acc -> Map.put(acc, auth.name, auth.describe(ctx)) end
      ),
      resources: ctx.version.resources
        |> Enum.map(&{&1.name, resource(%{ctx |
             resource_path: [&1],
             resource: &1,
           })})
        |> Enum.filter(fn {name, desc} ->
             !Enum.empty?(desc.actions) && Enum.empty?(desc.resources)
           end)
        |> Map.new,
      meta: %{namespace: "meta"}
    }
  end

  def resource(ctx) do
    %{
      actions: ctx.resource.actions
        |> Enum.map(&{&1.name, action(%{ctx | action: &1})})
        |> Enum.filter(fn {name, desc} -> not is_nil(desc) end)
        |> Map.new,
      resources: ctx.resource.resources
        |> Enum.map(&{&1.name, resource(%{ctx |
             resource_path: ctx.resource_path ++ [&1],
             resource: &1,
           })})
        |> Enum.filter(fn {name, desc} ->
             !Enum.empty?(desc.actions) && Enum.empty?(desc.resources)
           end)
        |> Map.new,
    }
  end

  def action(ctx) do
    method = ctx.action.method |> Atom.to_string |> String.upcase
    route = Path.join(
      [ctx.prefix] ++
      Enum.map(ctx.resource_path, &(&1.route)) ++
      [ctx.action.route]
    ) |> ctx.action.resolve_route(ctx.resource_path)

    with {:ok, input} <- io(ctx, :input),
         {:ok, output} <- io(ctx, :output) do
      %{
        auth: ctx.action.auth,
        description: ctx.action.desc,
        aliases: ctx.action.aliases,
        blocking: false, # TODO
        input: input,
        output: output,
        examples: [], # TODO
        meta: nil, # TODO
        url: route,
        method: method,
        help: Path.join([route, "method=#{ctx.action.method}"]),
      }
    else
      {:error, msg} ->
        nil
    end
  end

  def io(ctx, dir) do
    v = ctx.action.params(dir)

    if is_nil(v) do
      case authorize_params(nil, ctx, dir) do
        {:error, msg} ->
          {:error, msg}

        {:ok, nil} ->
          {:ok, nil}
      end

    else
      authorized_params = v
        |> Enum.map(&{&1.name, &1})
        |> Map.new
        |> authorize_params(ctx, dir)

      case authorized_params do
        {:error, msg} ->
          {:error, msg}

        {:ok, nil} ->
          {:ok, nil}

        {:ok, params} ->
          {:ok, %{
            layout: apply(ctx.action.io(dir), :layout, []),
            namespace: ctx.resource.name(),
            parameters: params(ctx, params),
          }}
      end
    end
  end

  def params(ctx, param_list) do
    Enum.reduce(
      param_list,
      %{},
      fn {name, p}, acc -> Map.put(acc, name, param(p)) end
    )
  end

  def param(p) do
    desc = %{
      label: p.label,
      description: p.description,
      type: p.type |> Atom.to_string |> String.capitalize,
      default: p.default,
    }

    case p.type do
      :resource ->
        Map.merge(desc, %{
          resource_path: Enum.map(p.resource_path, &(&1.name)),
          value_id: p.value_id || "id",
          value_label: p.value_label || "label"
        })

      _ ->
        desc
    end
  end

  defp authorize_params(params, ctx, :input) do
    ret = HaveAPI.Authorization.authorize(%HaveAPI.Request{
      context: ctx,
      conn: ctx.conn,
      user: ctx.user,
      input: params,
    })

    case ret do
      {:ok, data} ->
        {:ok, data.input}

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp authorize_params(params, ctx, :output) do
    ret = HaveAPI.Authorization.authorize(%HaveAPI.Response{
      context: ctx,
      conn: ctx.conn,
      output: params,
    })

    case ret do
      {:ok, data} ->
        {:ok, data.output}

      {:error, msg} ->
        {:error, msg}
    end
  end
end
