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
      def conn, do: @api_conn

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

        def actions do
          HaveAPI.Client.actions(
            @top_mod.conn,
            @resource_path
          )
        end

        def resources do
          HaveAPI.Client.resources(@top_mod.conn, @resource_path)
        end

        for r <- HaveAPI.Client.resources(conn, path) do
          @subresource_name r

          def unquote(:"#{r}")() do
            name = (@resource_path ++ [@subresource_name])
              |> Enum.map(&Macro.camelize/1)
              |> Enum.join(".")

            :"#{@top_mod}.Resource.#{Macro.camelize(name)}"
          end
        end

        for a <- HaveAPI.Client.actions(conn, path) do
          @action_name a

          def unquote(:"#{a}")() do
            apply(__MODULE__, String.to_atom(@action_name), [[]])
          end

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

      def unquote(:"#{resource_name}")() do
        @resource_mod
      end
    end
  end
end
