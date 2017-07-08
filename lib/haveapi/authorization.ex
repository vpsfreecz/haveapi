defmodule HaveAPI.Authorization do
  def authorize(%HaveAPI.Request{} = req) do
    ret = do_authorize(
      req.input,
      req.context.action.authorize(req, req.user),
      []
    )

    case ret do
      {:error, msg} ->
        {:error, msg, http_status: 403}

      data ->
        {:ok, %{req | input: data}}
    end
  end

  def authorize(%HaveAPI.Response{} = res) do
    ret = do_authorize(
      res.output,
      res.context.action.authorize(res, res.context.user),
      [HaveAPI.Meta.namespace]
    )

    case ret do
      {:error, msg} ->
        {:error, msg, http_status: 403}

      data ->
        {:ok, %{res | output: data}}
    end
  end

  defp do_authorize(_data, :deny, _ignore), do: {:error, "Access not authorized"}
  defp do_authorize(_data, {:deny, msg}, _ignore), do: {:error, msg}
  defp do_authorize(data, :allow, _ignore), do: data
  defp do_authorize(nil, {:allow, _opts}, _ignore), do: nil

  defp do_authorize(data, {:allow, opts}, ignore) when is_list(opts) do
    HaveAPI.Parameters.layout_aware(data, fn item ->
      Enum.reduce(
        opts,
        item,
        fn {k,v}, acc ->
          do_authorize_opts(acc, k, v, ignore)
        end
      )
    end)
  end

  defp do_authorize_opts(data, :blacklist, list, _ignore) when is_list(list) do
    Enum.filter(data, fn {k,_v} -> not (k in list) end) |> Map.new
  end

  defp do_authorize_opts(data, :whitelist, list, ignore) when is_list(list) do
    Enum.filter(data, fn {k,_v} -> not (k in ignore) && k in list end) |> Map.new
  end
end
