# HaveAPI
Server-side implementation of the [HaveAPI](https://github.com/vpsfreecz/haveapi)
protocol in Elixir in the form of a framework that can be used to create
self-descriptive RESTful web APIs. The framework features a DSL aimed at
creating API resources, actions and specifying input/output parameters. HaveAPI
handles everything from HTTP communication, authentication, parsing of input
parameters and formatting output, so that users can focus on their bussiness logic.

HaveAPI for Elixir is based on [Plug](https://github.com/elixir-lang/plug) and
[Plug.Router](https://hexdocs.pm/plug/Plug.Router.html#content), so in the end
it's a plug as well.

## Installation

Not available in Hex yet, but the package can be installed by adding `haveapi`
to your list of dependencies in `mix.exs`:

    ```elixir
    defp deps do
      [{:haveapi, path: "/path/to/this/repo"}]
    end
    ```

Then list both `cowboy` and `plug` as your application dependencies:

    ```elixir
    def application do
      [applications: [:cowboy, :plug]]
    end
    ```

## Example usage
The following example demostrates a fully functional API that can be used
with any of HaveAPI clients.

    ```elixir
    # Simple authentication handler for HTTP basic
    defmodule HttpBasic do
      use HaveAPI.Authentication.Basic

      def find_user(_request, "admin" = user, "1234"), do: user
      def find_user(_request, _user, _password), do: nil
    end

    # Define a REST resource
    defmodule Resource do
      use HaveAPI.Resource

      # Define actions
      # Index returns a list of items (resources)
      defmodule Index do
        use HaveAPI.Action.Index

        # Define output parameters
        output do
          integer :id
          string :label
        end

        # Authorize user's access to this action
        def authorize(_request, "admin"), do: :allow
        def authorize(_request, _user), do: :deny

        # This function is called when the action is requested
        def exec(_request) do
          # Return a list of maps with output parameters
          for x <- 1..10 do
            %{id: x, label: "Item ##{x}"}
          end
        end
      end

      # Show returns a single item (resource) specified by its id
      defmodule Show do
        use HaveAPI.Action.Show

        output do
          integer :id
          string :label
        end

        def authorize(_request, "admin"), do: :allow
        def authorize(_request, _user), do: :deny

        # Return a map with output parameters describing a single item
        def exec(request) do
          id = request.params[:resource_id]
          %{id: id, label: "Item ##{id}"}
        end
      end

      # Actions Index, Show, Create, Update and Delete are frequently used and
      # thus have templates that define their HTTP method, path and parameters.
      # We can also create custom actions with arbitrary settings.
      defmodule Custom do
        use HaveAPI.Action

        method :post
        route 'my_custom_action'

        input do
          string :action
        end

        output do
          string :result
        end

        def authorize(_request, "admin"), do: :allow
        def authorize(_request, _user), do: :deny

        def exec(request) do
          {:error, "Would execute action '#{request.input.action}'"}
        end
      end

      # Register actions to the resource
      actions [Index, Show, Custom]
    end

    # Define API, which can consist of several versions. Each API and each
    # version is basically a plug router.
    defmodule MyApi do
      use HaveAPI.Builder

      version "1.0" do
        # Register authentication providers
        auth_chain [HttpBasic]

        # Register API resources
        resources [Resource]
      end

      # Mount the API with all its versions, resources and actions under
      # a chosen prefix
      mount "/"
    end
    ```

Module `MyApi` is a plug router and can be started as such:

    $ iex -S mix
    iex> {:ok, _} = Plug.Adapters.Cowboy.http MyApi, []
    {:ok, #PID<...>}

Or you can add it to supervision tree:

    defmodule MyApp do
      use Application

      # See https://hexdocs.pm/elixir/Application.html
      # for more information on OTP Applications
      def start(_type, _args) do
        import Supervisor.Spec

        children = [
        # Define workers and child supervisors to be supervised
        Plug.Adapters.Cowboy.child_spec(:http, MyApi, [], [port: 4001])
        ]

        # See https://hexdocs.pm/elixir/Supervisor.html
        # for other strategies and supported options
        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end
    end

See [Plug documentation](https://hexdocs.pm/plug/readme.html) for more
information.
