defmodule HaveAPI.Validator.Confirmation do
  use HaveAPI.Validator

  def init(opts) do
    p = Keyword.fetch!(opts, :parameter)
    equal = Keyword.get(opts, :equal, true)

    %{
      parameter: p,
      equal: equal,
      message: opts[:message] || (if equal do
        "must be the same as #{p}"
      else
        "must be different from #{p}"
      end)
    }
  end

  def validate(%{equal: true} = opts, v, params) do
    return(opts, params[ opts[:parameter] ] === v)
  end

  def validate(%{equal: false} = opts, v, params) do
    return(opts, params[ opts[:parameter] ] !== v)
  end

  def return(_opts, true), do: :ok
  def return(opts, false), do: {:error, [opts.message]}
end
