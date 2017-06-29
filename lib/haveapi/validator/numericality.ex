defmodule HaveAPI.Validator.Numericality do
  use HaveAPI.Validator

  def name, do: :number

  def init(opts) do
    chain = Enum.map(
      opts,
      fn
        {:min, v} -> {:min, [v], "has to be minimally #{v}"}
        {:max, v} -> {:max, [v], "has to be maximally #{v}"}
        {:even, true} -> {:even, [], "has to be even"}
        {:odd, true} -> {:odd, [], "has to be odd"}
        {:step, v} -> {:step, [v, opts[:min]], "has to be in steps of #{v}"}
        {:mod, v} -> {:mod, [v], "mod #{v} must equal zero"}
        {:message, _} -> nil
        {k, v} -> raise "#{__MODULE__}: unknown option #{inspect({k, v})}"
      end
    ) |> Enum.filter(&(not is_nil(&1)))

    %{chain: chain, description: mkdescription(chain)}
  end

  def describe(%{description: desc}), do: desc

  def validate(%{chain: chain}, v, _params) do
    Enum.reduce(
      chain,
      [],
      fn
        {func, args, msg}, acc -> return_msg(acc, do_validate(func, [v | args]), msg)
      end
    ) |> return
  end

  defp mkdescription(chain) do
    chain
    |> Enum.map(
      fn
        {k, [], _msg} -> {k, true}
        {k, [h|_t], _msg} -> {k, h}
      end
    )
    |> Map.new
    |> Map.put(:message, Enum.map(chain, fn {_k, _args, msg} -> msg end) |> Enum.join("; "))
  end

  defp return_msg(acc, true, _msg), do: acc
  defp return_msg(acc, false, msg), do: [msg | acc]

  defp return([]), do: :ok
  defp return(errors), do: {:error, errors}

  defp do_validate(:min, [v, min]), do: v >= min
  defp do_validate(:max, [v, max]), do: v <= max
  defp do_validate(:even, [v]), do: rem(v, 2) == 0
  defp do_validate(:odd, [v]), do: rem(v, 2) == 1
  defp do_validate(:step, [v, step, nil]), do: rem(v, step) == 0
  defp do_validate(:step, [v, step, min]), do: rem(v - min, step) == 0
  defp do_validate(:mod, [v, mod]), do: rem(v, mod) == 0
end
