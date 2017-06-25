defmodule HaveAPI.AuthorizationTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule BasicAuth do
      use HaveAPI.Authentication.Basic

      def find_user(_req, "user", "1234"), do: "user"
      def find_user(_req, "admin", "1234"), do: "admin"
      def find_user(_req, _user, _pass), do: nil
    end

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule DefaultNoAuth do
        use HaveAPI.Action

        auth false
        route "%{action}"

        def exec(_req), do: :ok
      end

      defmodule DefaultWithAuth do
        use HaveAPI.Action

        auth true
        route "%{action}"

        def exec(_req), do: :ok
      end

      defmodule DenyAtom do
        use HaveAPI.Action

        auth true
        route "%{action}"

        def authorize(_, _), do: :deny
        def exec(_req), do: :ok
      end

      defmodule DenyMsg do
        use HaveAPI.Action

        auth true
        route "%{action}"

        def authorize(_, _), do: {:deny, "test"}
        def exec(_req), do: :ok
      end

      defmodule AllowAtom do
        use HaveAPI.Action

        auth true
        route "%{action}"

        def authorize(_, _), do: :allow
        def exec(_req), do: :ok
      end

      defmodule WhitelistOutput do
        use HaveAPI.Action

        auth true
        route "%{action}"

        output do
          string :str1
          string :str2
          string :secret
        end

        def authorize(_, "user"), do: {:allow, whitelist: [:str1, :str2]}
        def authorize(_, "admin"), do: :allow
        def exec(_req), do: %{str1: "one", str2: "two", secret: "noway"}
      end

      defmodule BlacklistOutput do
        use HaveAPI.Action

        auth true
        route "%{action}"

        output do
          string :str1
          string :str2
          string :secret
        end

        def authorize(_, "user"), do: {:allow, blacklist: [:secret]}
        def authorize(_, "admin"), do: :allow
        def exec(_req), do: %{str1: "one", str2: "two", secret: "noway"}
      end

      defmodule WhitelistInput do
        use HaveAPI.Action

        auth true
        route "%{action}"

        input do
          string :str1
          string :str2
          string :secret
        end

        output do
          string :str1
          string :str2
          string :secret
        end

        def authorize(%HaveAPI.Request{}, "user"), do: {:allow, whitelist: [:str1, :str2]}
        def authorize(%HaveAPI.Request{}, "admin"), do: :allow
        def authorize(_, _), do: :allow
        def exec(req), do: req.input
      end

      defmodule BlacklistInput do
        use HaveAPI.Action

        auth true
        route "%{action}"

        input do
          string :str1
          string :str2
          string :secret
        end

        output do
          string :str1
          string :str2
          string :secret
        end

        def authorize(%HaveAPI.Request{}, "user"), do: {:allow, blacklist: [:secret]}
        def authorize(%HaveAPI.Request{}, "admin"), do: :allow
        def authorize(_, _), do: :allow
        def exec(req), do: req.input
      end

      defmodule AdminOnly do
        use HaveAPI.Action

        auth true
        route "%{action}"

        def authorize(_, "admin"), do: :allow
        def authorize(_, _), do: :deny
      end

      actions [
        DefaultNoAuth,
        DefaultWithAuth,
        AllowAtom,
        DenyAtom,
        DenyMsg,
        WhitelistOutput,
        BlacklistOutput,
        WhitelistInput,
        BlacklistInput,
        AdminOnly,
      ]
    end

    defmodule AdminResource do
      use HaveAPI.Resource

      defmodule AdminOnly do
        use HaveAPI.Action

        auth true
        route "%{action}"

        def authorize(_, "admin"), do: :allow
        def authorize(_, _), do: :deny
      end

      actions [AdminOnly]
    end

    version "1.0" do
      auth_chain [BasicAuth]
      resources [MyResource, AdminResource]
    end

    mount "/"
  end

  test "defaults to authorized when authentication is not enforced" do
    conn = call_action(Api, "myresource", "defaultnoauth")

    assert conn.status == 200
    assert conn.resp_body["status"] === true
  end

  test "defaults to not authorized when authentication is enforced" do
    conn = call_action(Api, "myresource", "defaultwithauth")

    assert conn.status == 400
    assert conn.resp_body["status"] === false
  end

  test "is denied by :deny" do
    conn = call_action(Api, "myresource", "denyatom", basic: {"user", "1234"})

    assert conn.status == 400
    assert conn.resp_body["status"] === false
  end

  test "is denied with message" do
    conn = call_action(Api, "myresource", "denymsg", basic: {"user", "1234"})

    assert conn.status == 400
    assert conn.resp_body["status"] === false
    assert conn.resp_body["message"] == "test"
  end

  test "is authorized by :allow" do
    conn = call_action(Api, "myresource", "allowatom", basic: {"user", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
  end

  test "it whitelists output parameters" do
    conn = call_action(Api, "myresource", "whitelistoutput", basic: {"user", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    refute Map.has_key?(conn.resp_body["response"]["myresource"], "secret")

    conn = call_action(Api, "myresource", "whitelistoutput", basic: {"admin", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["myresource"], "secret")
  end

  test "it blacklists output parameters" do
    conn = call_action(Api, "myresource", "blacklistoutput", basic: {"user", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    refute Map.has_key?(conn.resp_body["response"]["myresource"], "secret")

    conn = call_action(Api, "myresource", "blacklistoutput", basic: {"admin", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["myresource"], "secret")
  end

  test "it whitelists input parameters" do
    conn = call_action(
      Api, "myresource", "whitelistinput",
      basic: {"user", "1234"},
      input: %{str1: "one", str2: "two", secret: "noway"}
    )

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    refute Map.has_key?(conn.resp_body["response"]["myresource"], "secret")

    conn = call_action(
      Api, "myresource", "whitelistinput",
      basic: {"admin", "1234"},
      input: %{str1: "one", str2: "two", secret: "noway"}
    )

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["myresource"], "secret")
  end

  test "it blacklists input parameters" do
    conn = call_action(
      Api, "myresource", "blacklistinput",
      basic: {"user", "1234"},
      input: %{str1: "one", str2: "two", secret: "noway"}
    )

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    refute Map.has_key?(conn.resp_body["response"]["myresource"], "secret")

    conn = call_action(
      Api, "myresource", "blacklistinput",
      basic: {"admin", "1234"},
      input: %{str1: "one", str2: "two", secret: "noway"}
    )

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["myresource"], "secret")
  end

  test "it filters actions in documentation" do
    conn = call_api(Api, :options, "/v1.0", nil, nil, basic: {"user", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["resources"], "myresource")
    refute Map.has_key?(conn.resp_body["response"]["resources"]["myresource"]["actions"], "adminonly")

    conn = call_api(Api, :options, "/v1.0", nil, nil, basic: {"admin", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["resources"], "myresource")
    assert Map.has_key?(conn.resp_body["response"]["resources"]["myresource"]["actions"], "adminonly")
  end

  test "it filters resources in documentation" do
    conn = call_api(Api, :options, "/v1.0", nil, nil, basic: {"user", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["resources"], "myresource")
    refute Map.has_key?(conn.resp_body["response"]["resources"], "adminresource")

    conn = call_api(Api, :options, "/v1.0", nil, nil, basic: {"admin", "1234"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"]["resources"], "myresource")
    assert Map.has_key?(conn.resp_body["response"]["resources"], "adminresource")
    assert Map.has_key?(conn.resp_body["response"]["resources"]["adminresource"]["actions"], "adminonly")
  end
end
