defmodule HaveAPI.Authentication.TokenTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule MyToken do
    use HaveAPI.Authentication.Token

    @token "abcd1234"

    def generate_token, do: @token

    def find_user_by_credentials(_conn, "admin" = user, "1234"), do: user
    def find_user_by_credentials(_conn, _user, _password), do: nil

    def save_token(_conn, _user, _token, _lifetime, _interval) do
      now = DateTime.utc_now
      {:ok, %{now | year: now.year+1}}
    end

    def find_user_by_token(_conn, @token), do: "admin"
    def find_user_by_token(_conn, token), do: nil

    def renew_token(_conn, _user, _token) do
      now = DateTime.utc_now
      {:ok, %{now | year: now.year+1}}
    end
  end

  defmodule MyResource do
    use HaveAPI.Resource

    defmodule Test do
      use HaveAPI.Action

      method :get
      route "%{action}"

      output do
        string :user
      end

      def authorize(_req, _user), do: :allow

      def exec(req), do: %{user: req.user}
    end

    actions [Test]
  end

  defmodule Api do
    use HaveAPI.Builder

    version "1.0" do
      auth_chain [MyToken]
      resources [MyResource]
    end

    mount "/"
  end

  describe "general function" do
    setup do
      [request: "/v1.0/_auth/token",
       renew: "/v1.0/_auth/token/renew",
       token: "abcd1234"]
    end

    test "issues token on valid credentials", context do
      conn = call_api(
        Api,
        :post,
        context[:request],
        "token",
        %{login: "admin", password: "1234", lifetime: "fixed"}
      )

      assert conn.status === 200
      assert conn.resp_body["response"]["token"]["token"] == context[:token]
    end

    test "does not issue token on invalid credentials", context do
      tests = [
        {"admin", "123"},
        {"admin", "1235"},
        {"admin", ""},
        {"", ""},
        {"", "nope"},
        {"test", "nope"},
      ]

      for {user, pass} <- tests do
        conn = call_api(
          Api,
          :post,
          context[:request],
          "token",
          %{login: user, password: pass, lifetime: "fixed"}
        )

        assert conn.status === 400
      end
    end

    test "accepts valid lifetimes", context do
      for v <- ~w(fixed renewable_manual renewable_auto permanent) do
        conn = call_api(
          Api,
          :post,
          context[:request],
          "token",
          %{login: "admin", password: "1234", lifetime: v}
        )

        assert conn.status === 200
        assert conn.resp_body["response"]["token"]["token"] == context[:token]
      end
    end

    test "rejects invalid lifetimes", context do
      for v <- ~w(fixedd renewable_manuall rrenewable_auto pernament) do
        conn = call_api(
          Api,
          :post,
          context[:request],
          "token",
          %{login: "admin", password: "1234", lifetime: v}
        )

        assert conn.status === 400
      end
    end

    test "token can be renewed when authenticated", context do
      conn = call_api(Api, :post, context[:renew], nil, nil, token: context[:token])

      assert conn.status === 200
      assert Map.has_key?(conn.resp_body["response"]["token"], "valid_to")
    end

    test "token cannot be renewed when not authenticated", context do
      conn = call_api(Api, :post, context[:renew], nil, nil, token: "invalidtoken")

      assert conn.status === 403
    end
  end
end
