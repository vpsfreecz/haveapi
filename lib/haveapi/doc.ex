defmodule HaveAPI.Doc do
  def api(resources) do
    %{versions: %{1 => version(resources)}}
  end

  def version(resources) do
    %{
      authentication: %{},
      resources: Enum.reduce(
        resources,
        %{},
        fn r, acc -> Map.put(acc, r.name, resource(r)) end
      ),
      meta: %{namespace: "meta"}
    }
  end

  def resource(res) do
    %{actions: Enum.reduce(
      res.actions,
      %{},
      fn a, acc -> Map.put(acc, a.name, action(a)) end
    )}
  end

  def action(act) do
    method = Atom.to_string(act.method) |> String.upcase

    %{
      auth: false, # TODO
      description: act.desc,
      aliases: act.aliases,
      blocking: false, # TODO
      input: nil, # TODO
      output: nil, # TODO
      examples: [], # TODO
      meta: nil, # TODO
      url: act.route,
      method: method,
      help: "#{act.route}?method=#{method}"
    }
  end
end
