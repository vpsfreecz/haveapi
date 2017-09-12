defmodule HaveAPI.Action.Input do
  def fetch_path_parameters(req) do
    %{req | params: Enum.map(
      req.conn.path_params,
      fn {k,v} -> {String.to_atom(k), v} end
    )}
  end

  def fetch_parameters(req) do
    if req.context.action.method == :get do
      do_fetch_parameters(req, req.conn.query_params)

    else
      do_fetch_parameters(req, req.conn.body_params)
    end
  end

  defp do_fetch_parameters(req, data) do
    with {:ok, input} <- do_fetch_parameters(req, data, :input),
         {:ok, meta} <- do_fetch_parameters(req, data, :meta) do
      {:ok, %{req | input: input, meta: meta}}

    else
      {:error, errors} ->
        {:error, "Input parameters not valid", errors: errors}
    end
  end

  defp do_fetch_parameters(req, data, :input) do
    HaveAPI.Parameters.extract(
      req.context.action.params(:input),
      req.context.resource.name,
      data
    )
  end

  defp do_fetch_parameters(req, data, :meta) do
    if req.context.action.has_meta?(:global) do
      HaveAPI.Parameters.extract(
        req.context.action.meta(:global).params(:input),
        Atom.to_string(HaveAPI.Meta.namespace),
        data
      )

    else
      {:ok, nil}
    end
  end
end
