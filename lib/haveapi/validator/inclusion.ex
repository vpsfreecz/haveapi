defmodule HaveAPI.Validator.Inclusion do
  use HaveAPI.Validator

  def name, do: :include

  def init(opts) do
    %{
      values: Keyword.fetch!(opts, :values),
      message: opts[:message] || "%{value} cannot be used"
    }
  end

  def validate(%{values: values} = opts, v, _params) when is_list(values) do
    return(opts, v in values)
  end

  def validate(%{values: values} = opts, v, _params) when is_map(values) do
    return(opts, Map.has_key?(values, v))
  end

  def return(_opts, true), do: :ok
  def return(opts, false), do: {:error, [opts.message]}
end
