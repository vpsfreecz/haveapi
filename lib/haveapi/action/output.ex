defmodule HaveAPI.Action.Output do
  def build(%HaveAPI.Request{} = req, data) do
    build(
      data,
      req.context.action.layout(:output),
      %HaveAPI.Response{context: req.context, conn: req.conn}
    )
  end

  def build(:ok, nil, res) do
    %{res | status: true}
  end

  def build(%HaveAPI.Response{} = res, _layout, _res), do: res

  def build(data, :hash, res) when is_map(data) do
    %{res | status: true, output: data}
  end

  def build({:ok, data}, :hash, res) when is_map(data) do
    %{res | status: true, output: data}
  end

  def build({:ok, data, meta}, :hash, res) when is_map(meta) do
    %{res | status: true, output: data, meta: meta}
  end

  def build(data, :hash_list, res) when is_list(data) do
    %{res | status: true, output: data}
  end

  def build({:ok, data}, :hash_list, res) when is_list(data) do
    %{res | status: true, output: data}
  end

  def build({:ok, data, meta}, :hash_list, res) when is_map(meta) do
    %{res | status: true, output: data, meta: meta}
  end

  def build({:error, msg}, nil, res) when is_binary(msg) do
    %{res | status: false, message: msg}
  end

  def build({:error, msg}, _layout, res) when is_binary(msg) do
    %{res | status: false, message: msg}
  end

  def build({:error, msg, opts}, _layout, res) when is_binary(msg) and is_list(opts) do
    %{res | status: false, message: msg, errors: opts[:errors], http_status: opts[:http_status]}
  end

  def build(_, _, res) do
    %{res | status: false, message: "Server error occurred.", http_status: 500}
  end

  def filter(%HaveAPI.Response{output: nil} = res, _) do
    {:ok, res}
  end

  def filter(res, :hash) do
    output = HaveAPI.Parameters.filter(
      res.context,
      res.context.action.params(:output),
      res.output
    )

    case output do
      {:ok, data} ->
        {:ok, %{res | output: data}}

      {:error, errors} ->
        {:error, "Output parameters not valid", errors: errors, http_status: 500}
    end
  end

  def filter(res, :hash_list) do
    {ret, errors} = Enum.reduce_while(
      res.output,
      {[], %{}},
      fn item, {ret, errors} ->
        output = HaveAPI.Parameters.filter(
          res.context,
          res.context.action.params(:output),
          item
        )

        case output do
          {:ok, data} ->
            {:cont, {[data | ret], errors}}

          {:error, errors} ->
            {:halt, {ret, errors}}
        end
      end
    )

    if Enum.empty?(errors) do
      {:ok, %{res | output: Enum.reverse(ret)}}

    else
      {:error, "Output parameters not valid", errors: errors, http_status: 500}
    end
  end

  def filter_meta(res) do
    if res.context.action.has_meta?(:global) && res.meta do
      params = res.context.action.meta(:global).params(:output)

      if params do
        meta = HaveAPI.Parameters.filter(res.context, params, res.meta)

        case meta do
          {:ok, meta} ->
            {:ok, %{res | meta: meta}}

          {:error, errors} ->
            {:error, "Output metadata parameters not valid", errors: errors}
        end

      else
        {:ok, %{res | meta: nil}}
      end

    else
      {:ok, res}
    end
  end
end
