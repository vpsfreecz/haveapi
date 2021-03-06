defmodule HaveAPI.Parameters.Dsl do
  defmacro __using__(opts) do
    quote do
      import HaveAPI.Parameters.Dsl, only: :macros

      @haveapi_params []
      @haveapi_layout unquote(opts[:layout])
      @before_compile HaveAPI.Parameters.Dsl

      defmacro __using__(only: params) do
        quote do
          only = unquote(params)

          Enum.filter_map(
            unquote(__MODULE__).params,
            &(&1.name in only),
            &(@haveapi_params [&1 | @haveapi_params])
          )
        end
      end

      defmacro __using__(except: params) do
        quote do
          except = unquote(params)

          Enum.filter_map(
            unquote(__MODULE__).params,
            &(not (&1.name in except)),
            &(@haveapi_params [&1 | @haveapi_params])
          )
        end
      end

      defmacro __using__(_opts) do
        quote do
          Enum.each(unquote(__MODULE__).params, &(@haveapi_params [&1 | @haveapi_params]))
        end
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def layout do
        @haveapi_layout
      end

      def params do
        Enum.reverse(@haveapi_params)
      end
    end
  end

  Enum.each(
    [:string, :text, :integer, :float, :datetime, :boolean, :custom],
    fn v ->
      defmacro unquote(:"#{v}")(name, opts \\ []) do
        type = unquote(v)

        quote bind_quoted: [mod: __MODULE__, name: name, opts: opts, type: type] do
          @haveapi_params [mod.mkparam(type, name, opts) | @haveapi_params]
        end
      end
    end
  )

  defmacro resource(resource_list, opts \\ []) do
    quote bind_quoted: [mod: __MODULE__, resource_list: resource_list, opts: opts] do
      @haveapi_params [mod.mkparam(:resource, resource_list, opts) | @haveapi_params]
    end
  end

  defmacro patch(param, opts) do
    quote bind_quoted: [mod: __MODULE__, param: param, opts: opts] do
      @haveapi_params Enum.map(@haveapi_params, fn p ->
        if p.name == param do
          mod.patch_param(p, opts)

        else
          p
        end
      end)
    end
  end

  def mkparam(:resource, resource_list, opts) do
    %HaveAPI.Parameter{
      name: opts[:name] || String.to_atom(List.last(resource_list).name),
      type: :resource,
      label: opts[:label],
      description: opts[:description],
      resource_path: resource_list,
      value_id: opts[:value_id],
      value_label: opts[:value_label],
    }
  end

  def mkparam(type, name, opts) do
    %HaveAPI.Parameter{
      name: name,
      type: type,
      label: opts[:label],
      description: opts[:description],
      default: opts[:default] || :_none,
      fill: opts[:fill],
      validators: mkvalidators(opts[:validate]),
    }
  end

  def mkvalidators(nil), do: nil
  def mkvalidators(opts) when is_list(opts) do
    Enum.reduce(
      opts,
      [],
      fn {k, v}, acc ->
        case mkvalidator(k, v) do
          {nil, _mod} ->
            acc

          {mod, opts} ->
            [{mod, mod.init(opts)} | acc]
        end
      end
    ) |> Enum.reverse
  end

  # Presence
  def mkvalidator(:required, true) do
    {HaveAPI.Validator.Presence, []}
  end
  def mkvalidator(:required, false) do
    {nil, HaveAPI.Validator.Presence}
  end
  def mkvalidator(:required, opts) when is_list(opts) do
    {HaveAPI.Validator.Presence, opts}
  end

  # Acceptance
  def mkvalidator(:accept, opts) when is_list(opts) do
    {HaveAPI.Validator.Acceptance, opts}
  end
  def mkvalidator(:accept, v) do
    {HaveAPI.Validator.Acceptance, [value: v]}
  end

  # Inclusion
  def mkvalidator(:include, opts) when is_list(opts) do
    {HaveAPI.Validator.Inclusion, opts}
  end

  # Exclusion
  def mkvalidator(:exclude, opts) when is_list(opts) do
    {HaveAPI.Validator.Exclusion, opts}
  end

  # Format
  def mkvalidator(:format, opts) when is_list(opts) do
    {HaveAPI.Validator.Format, opts}
  end
  def mkvalidator(:format, rx) do
    if Regex.regex?(rx) do
      {HaveAPI.Validator.Format, [rx: rx]}

    else
      raise "#{inspect(rx)} is not a regex"
    end
  end

  # Confirmation
  def mkvalidator(:confirm, param) when is_atom(param) do
    {HaveAPI.Validator.Confirmation, [parameter: param]}
  end
  def mkvalidator(:confirm, opts) when is_list(opts) do
    {HaveAPI.Validator.Confirmation, opts}
  end

  # Length
  def mkvalidator(:length, n) when is_integer(n) do
    {HaveAPI.Validator.Length, [equals: n]}
  end
  def mkvalidator(:length, %Range{first: first, last: last}) do
    {HaveAPI.Validator.Length, [min: first, max: last]}
  end
  def mkvalidator(:length, opts) when is_list(opts) do
    {HaveAPI.Validator.Length, opts}
  end

  # Numericality
  def mkvalidator(:number, :even) do
    {HaveAPI.Validator.Numericality, [even: true]}
  end
  def mkvalidator(:number, :odd) do
    {HaveAPI.Validator.Numericality, [odd: true]}
  end
  def mkvalidator(:number, %Range{first: first, last: last}) do
    {HaveAPI.Validator.Numericality, [min: first, max: last]}
  end
  def mkvalidator(:number, opts) when is_list(opts) do
    {HaveAPI.Validator.Numericality, opts}
  end

  def mkvalidator(k, v) do
    raise "Unknown validator '#{k}' with option '#{inspect(v)}'"
  end

  def patch_param(p, opts) do
    changeable = ~w(type label description default fill)a

    changes = Enum.reduce(
      changeable,
      %{},
      fn k, acc ->
        if Keyword.has_key?(opts, k) do
          Map.put(acc, k, opts[k])

        else
          acc
        end
      end
    )

    p
    |> Map.merge(changes)
    |> merge_validators(p.validators || [], opts[:validate] || [])
  end

  def merge_validators(p, _existing, []), do: p

  def merge_validators(p, [], validators) do
    %{p | validators: mkvalidators(validators)}
  end

  def merge_validators(p, existing, validators) do
    merged = Enum.reduce(
      validators,
      existing,
      fn {k,v}, acc ->
        case mkvalidator(k, v) do
          {nil, mod} ->
            Keyword.delete(acc, mod)

          {mod, opts} ->
            built_opts = mod.init(opts)
            Keyword.update(acc, mod, built_opts, fn _ -> built_opts end)
        end
      end
    )

    %{p | validators: merged}
  end
end
