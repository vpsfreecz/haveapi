defmodule HaveAPI.Parameter.Input do
  @spec coerce(atom, any) :: any
  def coerce(:string, v) when is_binary(v), do: {:ok, v}

  def coerce(:text, v), do: coerce(:string, v)

  def coerce(:integer, v) when is_integer(v), do: {:ok, v}

  def coerce(:float, v) when is_float(v), do: {:ok, v}

  def coerce(:boolean, v) when is_boolean(v), do: {:ok, v}
  def coerce(:boolean, "1"), do: {:ok, true}
  def coerce(:boolean, "0"), do: {:ok, false}

  def coerce(:datetime, v) when is_binary(v) do
    Enum.reduce_while(
      [:date, :datetime],
      nil,
      fn type, _acc ->
        case datetime(type, v) do
          {:ok, date} ->
            {:halt, {:ok, date}}

          # TODO: handle offset?
          {:ok, dt, _offset} ->
            {:halt, {:ok, dt}}

          {:error, atom} ->
            {:cont, {:error, "#{inspect(v)} is not in ISO 8601 format: #{atom}"}}
        end
      end
    )
  end

  def coerce(:resource, v), do: v

  def coerce(:custom, v), do: {:ok, v}

  def coerce(type, v), do: {:error, "#{inspect(v)} is not #{type}"}

  defp datetime(:date, v), do: Date.from_iso8601(v)
  defp datetime(:datetime, v), do: DateTime.from_iso8601(v)
end
