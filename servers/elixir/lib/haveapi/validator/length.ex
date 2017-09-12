defmodule HaveAPI.Validator.Length do
  use HaveAPI.Validator

  def init(opts) do
    if opts[:equals] && (opts[:min] || opts[:max]) do
      raise "cannot mix equals and min/max"
    end

    mkopts(opts, opts[:equals], opts[:min], opts[:max])
  end

  def validate(opts, v, _params), do: do_validate(opts, String.length(v))

  defp mkopts(opts, equals, nil, nil) when is_integer(equals) do
    %{
      equals: equals,
      message: opts[:message] || "length has to be #{equals}"
    }
  end

  defp mkopts(opts, nil, min, nil) when is_integer(min) do
    %{
      min: min,
      message: opts[:message] || "length has to be minimally #{min}"
    }
  end

  defp mkopts(opts, nil, nil, max) when is_integer(max) do
    %{
      max: max,
      message: opts[:message] || "length has to be maximally #{max}"
    }
  end

  defp mkopts(opts, nil, min, max) when is_integer(min) and is_integer(max) do
    %{
      min: min,
      max: max,
      message: opts[:message] || "length has to be in range <#{min}, #{max}>"
    }
  end

  defp do_validate(%{equals: n} = opts, len) when is_integer(n) do
    return(opts, n == len)
  end

  defp do_validate(%{min: min, max: max} = opts, len) when is_integer(min) and is_integer(max) do
    return(opts, len >= min && len <= max)
  end

  defp do_validate(%{min: min} = opts, len) when is_integer(min) do
    return(opts, len >= min)
  end

  defp do_validate(%{max: max} = opts, len) when is_integer(max) do
    return(opts, len <= max)
  end

  defp return(_opts, true), do: :ok
  defp return(opts, false), do: {:error, [opts.message]}
end
