defmodule HaveAPI.Validator.Presence do
  use HaveAPI.Validator

  def name, do: :present

  def init(opts) do
    empty = Keyword.get(opts, :empty, false)

    %{
      empty: empty,
      message: Keyword.get(
        opts,
        :message,
        (if empty, do: "must be present", else: "must be present and non-empty")
      )
    }
  end

  def validate(%{empty: true}, _v, _params), do: :ok
  def validate(opts, v, _params) when is_binary(v), do: not_empty(opts, String.trim(v))
  def validate(opts, v, _params), do: not_empty(opts, v)

  defp not_empty(opts, nil), do: {:error, [opts.message]}
  defp not_empty(opts, ""), do: {:error, [opts.message]}
  defp not_empty(_opts, _v), do: :ok
end
