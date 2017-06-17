defmodule HaveAPI.Authentication.Token do
  @callback find_user_by_credentials(%Plug.Conn{}, String.t, String.t) :: any
  @callback save_token(%Plug.Conn{}, any, String.t, Integer, Integer) :: DateTime
  @callback revoke_token(%Plug.Conn{}, any, String.t) :: any
  @callback renew_token(%Plug.Conn{}, any, String.t) :: any
  @callback find_user_by_token(%Plug.Conn{}, String.t) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
      alias HaveAPI.Authentication.Token, as: Provider

      provider = __MODULE__

      defmodule Token do
        use HaveAPI.Resource

        defmodule Request do
          use HaveAPI.Action

          @haveapi_provider provider

          method :post
          auth false

          input do
            # TODO: validators, proper lifetime & inverval handling
            string :login, label: "Login"
            string :password, label: "Password"
            string :lifetime, label: "Lifetime"
            integer :interval, label: "Interval",
              desc: "How long will requested token be valid, in seconds.",
              default: 60*5
          end

          output do
            string :token
            datetime :valid_to
          end

          def exec(req) do
            Provider.request(@haveapi_provider, req)
          end
        end

        defmodule Renew do
          use HaveAPI.Action

          route "renew"
          method :post

          input do
            # TODO
          end

          output do
            # TODO
          end

          def exec(req) do
            # TODO
          end
        end

        defmodule Revoke do
          use HaveAPI.Action

          input do
            # TODO
          end

          output do
            # TODO
          end

          def exec(req) do
            # TODO
          end
        end

        actions [Request, Renew, Revoke]
      end

      def name, do: :token

      def describe(ctx) do
        %{
          http_header: http_header(),
          query_parameter: query_parameter(),
          description: "The client authenticates with username and password and gets " <>
                       "a token. From this point, the password can be forgotten and " <>
                       "the token is used instead. Tokens can have different lifetimes, " <>
                       "can be renewed and revoked. The token is passed either via HTTP " <>
                       "header or query parameter.",
          resources: %{
            token: HaveAPI.Doc.resource(%{ctx |
              prefix: Path.join(ctx.prefix, "_auth"),
              resource_path: [Token],
              resource: Token
            })
          },
        }
      end

      def http_header, do: Provider.http_header

      def query_parameter, do: Provider.query_parameter

      def generate_token, do: Provider.generate_token

      defoverridable [http_header: 0, query_parameter: 0, generate_token: 0]

      def authenticate(conn), do: Provider.authenticate(__MODULE__, conn)

      def resources, do: [Token]
    end
  end

  def http_header, do: "X-HaveAPI-Auth-Token"

  def query_parameter, do: "_auth_token"

  def generate_token, do: :crypto.strong_rand_bytes(50) |> Base.encode16(case: :lower)

  def authenticate(provider, conn) do
    t = get_token(provider, conn)
    t && provider.find_user_by_token(conn, t)
  end

  defp get_token(provider, conn) do
    conn.query_params[provider.query_parameter] || get_header_token(provider, conn)
  end

  defp get_header_token(provider, conn) do
    header = provider.http_header |> String.downcase

    case Enum.find(conn.req_headers, fn {k, _} -> k == header end) do
      {_, token} ->
        token
      _ ->
        nil
    end
  end

  def request(provider, req) do
    user = provider.find_user_by_credentials(
      req.conn,
      req.input.login,
      req.input.password
    )

    if user do
      token = provider.generate_token

      %{
        token: token,
        valid_to: provider.save_token(
          req.conn,
          user,
          token,
          req.input[:lifetime],
          req.input[:interval]
        ),
      }

    else
      {:error, "bad login or password"}
    end
  end
end
