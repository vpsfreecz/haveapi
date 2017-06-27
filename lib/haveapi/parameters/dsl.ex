defmodule HaveAPI.Parameters.Dsl do
  defmacro __using__(opts) do
    quote do
      import HaveAPI.Parameters.Dsl, only: :macros

      Module.register_attribute __MODULE__, :haveapi_params, accumulate: true
      @haveapi_layout unquote(opts[:layout])
      @before_compile HaveAPI.Parameters.Dsl

      defmacro __using__(only: params) when is_list(params) do
        quote do
          only = unquote(params)

          Enum.filter_map(
            unquote(__MODULE__).params,
            &(&1.name in only),
            &(@haveapi_params &1)
          )
        end
      end

      defmacro __using__(except: params) when is_list(params) do
        quote do
          except = unquote(params)

          Enum.filter_map(
            unquote(__MODULE__).params,
            &(not (&1.name in except)),
            &(@haveapi_params &1)
          )
        end
      end

      defmacro __using__(_opts) do
        quote do
          Enum.each(unquote(__MODULE__).params, &(@haveapi_params &1))
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
          @haveapi_params mod.mkparam(type, name, opts)
        end
      end
    end
  )

  defmacro resource(resource_list, opts \\ []) do
    quote bind_quoted: [mod: __MODULE__, resource_list: resource_list, opts: opts] do
      @haveapi_params mod.mkparam(:resource, resource_list, opts)
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
          {mod, opts} ->
            [{mod, mod.init(opts)} | acc]

          nil ->
            acc
        end
      end
    ) |> Enum.reverse
  end

  # Presence
  def mkvalidator(:required, true) do
    {HaveAPI.Validator.Presence, []}
  end
  def mkvalidator(:required, false) do
    nil
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

  def mkvalidator(k, v) do
    raise "Unknown validator '#{k}' with option '#{inspect(v)}'"
  end
end
