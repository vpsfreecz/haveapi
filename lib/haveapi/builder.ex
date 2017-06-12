defmodule HaveAPI.Builder do
  defmacro __using__(_opts) do
    quote do
      import HaveAPI.Builder
      use Plug.Router
      
      plug :match
      plug :dispatch

      Module.register_attribute __MODULE__, :haveapi_resources, accumulate: true
      @before_compile HaveAPI.Builder
    end
  end
  
  defmacro resources(res) do
    quote do
      Enum.each(unquote(res), &(@haveapi_resources &1))
    end
  end

  defmacro resources() do
    quote do
      @haveapi_resources
    end
  end

  defmacro mount(prefix \\ "/") do
    quote bind_quoted: [prefix: prefix] do
      match prefix, via: :options do
        Plug.Conn.send_resp(
          binding()[:conn],
          200,
          Poison.encode!(HaveAPI.Doc.api(@haveapi_resources))
        )
      end

      Enum.each(@haveapi_resources, fn r ->
        Enum.each(r.actions, fn a ->
          @current_action a
          match Path.join([prefix, r.route, a.route]), via: a.method do
            HaveAPI.Action.execute(@current_action, binding()[:conn])
          end
        end)
      end)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def router do
        HaveAPI.Builder
      end
    end
  end
end
