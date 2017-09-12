defmodule HaveAPI.Parameter.Output do
  @spec coerce(atom, any) :: any
  def coerce(:string, v) when is_binary(v), do: {:ok, v}
  def coerce(:string, v) do
    if is_nil(String.Chars.impl_for(v)) do
      {:error, "#{inspect(v)} does not implement String.Chars protocol"}

    else
      {:ok, to_string(v)}
    end
  end

  def coerce(:text, v), do: coerce(:string, v)

  def coerce(:integer, v) when is_integer(v), do: {:ok, v}

  def coerce(:float, v) when is_float(v), do: {:ok, v}

  def coerce(:boolean, v) when is_boolean(v), do: {:ok, v}

  def coerce(:datetime, %DateTime{} = v), do: {:ok, DateTime.to_iso8601(v)}
  def coerce(:datetime, %Date{} = v), do: {:ok, Date.to_iso8601(v)}
  def coerce(:datetime, %NaiveDateTime{} = v) do
    {:ok, dt} = DateTime.from_naive(v, "Etc/UTC")
    {:ok, DateTime.to_iso8601(dt)}
  end

  def coerce(:custom, v), do: {:ok, v}

  def coerce(type, v), do: {:error, "#{inspect(v)} is not #{type}"}
end
