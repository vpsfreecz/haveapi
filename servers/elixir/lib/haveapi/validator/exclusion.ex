defmodule HaveAPI.Validator.Exclusion do
  use HaveAPI.Validator

  def name, do: :exclude

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

  def return(opts, true), do: {:error, [opts.message]}
  def return(_opts, false), do: :ok
end
