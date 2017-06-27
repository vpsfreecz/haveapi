defmodule HaveAPI.Validator.Acceptance do
  use HaveAPI.Validator

  def init(opts) do
    %{
      value: opts[:value],
      message: opts[:message] || "has to be '#{inspect(opts[:value])}'"
    }
  end

  def validate(%{value: v}, v, _params), do: :ok
  def validate(opts, _v, _params), do: {:error, [opts.message]}
end
