defmodule HaveAPI.Authentication.Token do
  @callback find_user_by_credentials(%Plug.Conn{}, String.t, String.t) :: any
  @callback save_token(%Plug.Conn{}, any, String.t, Integer, Integer) :: any
  @callback revoke_token(%Plug.Conn{}, any, String.t) :: any
  @callback renew_token(%Plug.Conn{}, any, String.t) :: any
  @callback find_user_by_token(%Plug.Conn{}, String.t) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      provider = __MODULE__

      defmodule Token do
        use HaveAPI.Resource

        defmodule Request do
          use HaveAPI.Action

          @haveapi_provider provider

          method :post

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
            user = @haveapi_provider.find_user_by_credentials(
              req.conn,
              req.input.login,
              req.input.password
            )

            if user do
              token = @haveapi_provider.generate_token
              @haveapi_provider.save_token(
                req.conn,
                user,
                token,
                req.input[:lifetime],
                req.input[:interval]
              )

              %{token: token, valid_to: "2017-12-31T00:00:00Z"}

            else
              {:error, "bad login or password"}
            end
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
              resource: Token
            })
          },
        }
      end

      def http_header, do: "X-HaveAPI-Auth-Token"

      def query_parameter, do: "_auth_token"

      def generate_token do
        :crypto.strong_rand_bytes(50) |> Base.encode16(case: :lower)
      end

      defoverridable [http_header: 0, query_parameter: 0, generate_token: 0]

      def authenticate(conn) do
        t = get_token(conn)
        t && find_user_by_token(conn, t)
      end

      def resources, do: [Token]

      defp get_token(conn) do
        conn.query_params[query_parameter()] || get_header_token(conn)
      end

      defp get_header_token(conn) do
        header = http_header() |> String.downcase

        case Enum.find(conn.req_headers, fn {k, v} -> k == header end) do
          {_, token} ->
            token
          _ ->
            nil
        end
      end
    end
  end
end
