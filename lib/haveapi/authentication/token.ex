defmodule HaveAPI.Authentication.Token do
  @callback find_user_by_credentials(
    conn :: Plug.Conn.t,
    username :: String.t,
    password :: String.t
  ) :: nil | any
  @callback save_token(
    conn :: Plug.Conn.t,
    user :: any,
    token :: String.t,
    lifetime :: atom,
    interval :: integer
  ) :: {:ok, DateTime.t} | {:error, any}
  @callback revoke_token(
    conn :: Plug.Conn.t,
    user :: any,
    token :: String.t
  ) :: :ok | {:error, String.t}
  @callback renew_token(
    conn :: Plug.Conn.t,
    user :: any,
    token :: String.t
  ) :: {:ok, DateTime.t} | {:error, String.t}
  @callback find_user_by_token(conn :: Plug.Conn.t, token :: String.t) :: nil | any

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
            string :login, label: "Login", validate: [required: true]
            string :password, label: "Password", validate: [required: true]
            string :lifetime, label: "Lifetime", validate: [
              required: true,
              include: [values: ~w(fixed renewable_manual renewable_auto permanent)],
            ]
            integer :interval, label: "Interval",
              desc: "How long will the requested token be valid, in seconds.",
              default: 60*5, fill: true
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

          @haveapi_provider provider

          route "%{action}"
          method :post

          output do
            datetime :valid_to
          end

          def authorize(_req, _user), do: :allow

          def exec(req) do
            Provider.renew(@haveapi_provider, req)
          end
        end

        defmodule Revoke do
          use HaveAPI.Action

          @haveapi_provider provider

          route "%{action}"
          method :post

          def authorize(_req, _user), do: :allow

          def exec(req) do
            Provider.revoke(@haveapi_provider, req)
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
      token_str = provider.generate_token
      ret = provider.save_token(
        req.conn,
        user,
        token_str,
        req.input[:lifetime],
        req.input[:interval]
      )

      case ret do
        {:ok, valid_to} ->
          %{
            token: token_str,
            valid_to: valid_to,
          }

        {:error, _} ->
          {:error, "unable to save the token"}
      end

    else
      {:error, "bad login or password"}
    end
  end

  def renew(provider, req) do
    case provider.renew_token(req.conn, req.user, get_token(provider, req.conn)) do
      {:ok, valid_to} ->
        %{valid_to: valid_to}

      {:error, msg} when is_binary(msg) ->
        {:error, msg}

      _ ->
        {:error, "unable to renew token", http_status: 500}
    end
  end

  def revoke(provider, req) do
    case provider.revoke_token(req.conn, req.user, get_token(provider, req.conn)) do
      :ok ->
        :ok

      {:error, msg} when is_binary(msg) ->
        {:error, msg}

      _ ->
        {:error, "unable to revoke token", http_status: 500}
    end
  end
end
