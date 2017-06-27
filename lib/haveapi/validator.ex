defmodule HaveAPI.Validator do
  @type opts :: map

  @callback name() :: String.t
  @callback init(keyword) :: opts
  @callback describe(opts) :: map
  @callback validate(opts, any, map) :: :ok | {:error, list}

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      def name do
        __MODULE__
        |> Module.split
        |> List.last
        |> String.downcase
        |> String.to_atom
      end

      def describe(opts), do: opts

      defoverridable [name: 0, describe: 1]
    end
  end

  # TODO: make it work with hash_list
  def validate(req) do
    validate(req.context.action.params(:input), req.input)
  end

  defp validate(nil, _data), do: :ok

  defp validate(params, data) do
    ret = Enum.reduce(
      params,
      %{},
      fn p, acc ->
        case do_validate(p, data) do
          :ok -> acc
          {:error, errors} -> Map.put(acc, p.name, errors)
        end
      end
    )

    if Enum.empty?(ret) do
      :ok

    else
      {:error, "Input parameters not valid", errors: ret, http_status: 400}
    end
  end

  defp do_validate(%HaveAPI.Parameter{validators: nil}, _item), do: :ok
  defp do_validate(%HaveAPI.Parameter{validators: []}, _item), do: :ok
  defp do_validate(p, nil), do: validate_missing(p)
  defp do_validate(p, data) do
    if Map.has_key?(data, p.name) do
      ret = Enum.reduce(
        p.validators,
        [],
        fn {validator, opts}, acc ->
          case validator.validate(opts, data[p.name], data) do
            :ok -> acc
            {:error, errors} -> Enum.concat(acc, errors)
          end
        end
      )

      if Enum.empty?(ret) do
        :ok

      else
        {:error, ret}
      end

    else
      validate_missing(p)
    end
  end

  defp validate_missing(p) do
    validator = Enum.find(p.validators, fn {mod, _opts} -> mod.name == :presence end)

    if validator do
      {presence, opts} = validator
      {:error, [presence.describe(opts).message]}

    else
      :ok
    end
  end
end
