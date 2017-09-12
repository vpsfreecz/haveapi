defmodule HaveAPI.Authorization do
  def authorize(%HaveAPI.Request{} = req) do
    ret = do_authorize(
      param_names(req.context.action.params(:input)),
      req.input,
      req.context.action.authorize(req, req.user),
      []
    )

    case ret do
      {:error, msg} ->
        {:error, msg, http_status: 403}

      {data, params} ->
        {:ok, %{req | input: data}, params}
    end
  end

  def authorize(%HaveAPI.Response{} = res) do
    ret = do_authorize(
      param_names(res.context.action.params(:output)),
      res.output,
      res.context.action.authorize(res, res.context.user),
      [HaveAPI.Meta.namespace]
    )

    case ret do
      {:error, msg} ->
        {:error, msg, http_status: 403}

      {data, _params} ->
        {:ok, %{res | output: data}}
    end
  end

  defp param_names(nil), do: []
  defp param_names(params), do: Enum.map(params, &(&1.name))

  defp do_authorize(_params, _data, :deny, _ignore), do: {:error, "Access not authorized"}
  defp do_authorize(_params, _data, {:deny, msg}, _ignore), do: {:error, msg}
  defp do_authorize(params, data, :allow, _ignore), do: {data, params}
  defp do_authorize(params, nil, {:allow, _opts}, _ignore), do: {nil, params}

  defp do_authorize(params, data, {:allow, opts}, ignore) when is_list(opts) do
    authorized = authorized_params(params, opts, ignore)
    {filter_data(authorized, data), authorized}
  end

  defp authorized_params(params, opts, ignore) do
    Enum.reduce(
      opts,
      params,
      fn {k,v}, acc ->
        do_authorize_opts(acc, k, v, ignore)
      end
    )
  end

  defp do_authorize_opts(params, :blacklist, list, _ignore) when is_list(list) do
    Enum.filter(params, fn p -> not (p in list) end)
  end

  defp do_authorize_opts(params, :whitelist, list, ignore) when is_list(list) do
    Enum.filter(params, fn p -> not (p in ignore) && p in list end)
  end

  defp filter_data(params, data) do
    data
    |> Enum.filter(fn {k, _v} -> k in params end)
    |> Enum.into(%{})
  end
end
