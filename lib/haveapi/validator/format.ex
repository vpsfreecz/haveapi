defmodule HaveAPI.Validator.Format do
  use HaveAPI.Validator

  def init(opts) do
    %{
      rx: Keyword.fetch!(opts, :rx),
      match: Keyword.get(opts, :match, true),
      message: opts[:message] || "%{value} cannot be used"
    }
  end

  def validate(%{match: true} = opts, v, _params) do
    return(opts, Regex.match?(opts[:rx], v))
  end

  def validate(%{match: false} = opts, v, _params) do
    return(opts, not Regex.match?(opts[:rx], v))
  end

  def return(_opts, true), do: :ok
  def return(opts, false), do: {:error, [opts.message]}
end
