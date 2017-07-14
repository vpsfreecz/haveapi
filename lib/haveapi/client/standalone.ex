defmodule HaveAPI.Client.Standalone do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias HaveAPI.Client
      alias HaveAPI.Client.Standalone

      Client.Http.start

      conn = Client.connect(
        Keyword.fetch!(opts, :url),
        opts[:version]
      )

      conn = if opts[:auth] do
        {method, opts} = opts[:auth]
        {:ok, conn} = Client.authenticate(conn, method, opts)
        conn

      else
        conn
      end

      @api_conn conn

      @doc "Access API connection options."
      def conn, do: @api_conn

      @doc "Returns a list of all top-level API resources."
      def resources, do: Client.resources(conn())

      for r <- Client.resources(conn) do
        Standalone.define_resource(conn, [r])
      end
    end
  end

  defmacro define_resource(conn, path) do
    quote bind_quoted: [conn: conn, path: path] do
      HaveAPI.Client.Standalone.define_single_resource(conn, path)

      for r <- HaveAPI.Client.resources(conn, path) do
        HaveAPI.Client.Standalone.define_single_resource(conn, path ++ [r])
      end
    end
  end

  defmacro define_single_resource(conn, path) do
    quote bind_quoted: [conn: conn, path: path] do
      top_mod = __MODULE__
      mod_name = path |> Enum.map(&Macro.camelize/1) |> Enum.join(".")
      resource_mod = :"#{__MODULE__}.Resource.#{mod_name}"
      resource_name = List.last(path)

      @resource_path path
      @resource_name resource_name
      @resource_mod resource_mod

      defmodule :"#{resource_mod}" do
        @top_mod top_mod
        @resource_path path
        @resource_name resource_name
        @moduledoc HaveAPI.Client.Standalone.doc(conn, path)

        @doc "List actions of this resource."
        @spec actions() :: list
        def actions do
          HaveAPI.Client.actions(
            @top_mod.conn,
            @resource_path
          )
        end

        @doc "List subresources of this resource."
        @spec actions() :: list
        def resources do
          HaveAPI.Client.resources(@top_mod.conn, @resource_path)
        end

        for r <- HaveAPI.Client.resources(conn, path) do
          name = (path ++ [r])
            |> Enum.map(&Macro.camelize/1)
            |> Enum.join(".")
          @subresource_mod :"#{top_mod}.Resource.#{Macro.camelize(name)}"

          @doc """
          Access resource module `#{HaveAPI.Client.Standalone.doc(:mod, @subresource_mod)}.`
          """
          def unquote(:"#{r}")() do
            @subresource_mod
          end
        end

        for a <- HaveAPI.Client.actions(conn, path) do
          @action_name a

          @doc """
          Call action `#{a}` with no additional parameters.

          #{HaveAPI.Client.Standalone.doc(conn, path, a)}
          """
          def unquote(:"#{a}")() do
            apply(__MODULE__, String.to_atom(@action_name), [[]])
          end

          @doc """
          Call action `#{a}` with custom connection options or additional parameters.

          #{HaveAPI.Client.Standalone.doc(conn, path, a)}
          """
          @spec unquote(:"#{a}")(map | list) :: map
          def unquote(:"#{a}")(conn_or_opts)
          def unquote(:"#{a}")(opts) when is_list(opts) do
            HaveAPI.Client.call(
              @top_mod.conn,
              @resource_path,
              @action_name,
              opts
            )
          end

          def unquote(:"#{a}")(conn) when is_map(conn) do
            HaveAPI.Client.call(
              conn,
              @resource_path,
              @action_name,
              []
            )
          end

          @doc """
          Call action `#{a}` with custom connection options and additional parameters.

          #{HaveAPI.Client.Standalone.doc(conn, path, a)}
          """
          def unquote(:"#{a}")(conn, opts) when is_map(conn) and is_list(opts) do
            HaveAPI.Client.call(
              conn,
              @resource_path,
              @action_name,
              opts
            )
          end
        end
      end

      @doc "Access resource module `#{HaveAPI.Client.Standalone.doc(:mod, @resource_mod)}`"
      def unquote(:"#{resource_name}")() do
        @resource_mod
      end
    end
  end

  def doc(:mod, mod) do
    mod
    |> Atom.to_string
    |> String.slice(String.length("Elixir.")..-1)
  end

  def doc(conn, resource_path) do
    HaveAPI.Client.resource(conn, resource_path).resource_desc["description"]
  end

  def doc(conn, resource_path, action_name) do
    HaveAPI.Client.action(conn, resource_path, action_name).action_desc["description"]
  end
end
