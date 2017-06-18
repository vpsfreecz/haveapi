defmodule HaveAPI.AuthenticationTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Auth do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule DefAuth do
        use HaveAPI.Action

        route "%{action}"

        def exec(_), do: :ok
      end

      defmodule NoAuth do
        use HaveAPI.Action
        route "%{action}"
        auth false

        def exec(_), do: :ok
      end

      defmodule WithAuth do
        use HaveAPI.Action
        route "%{action}"
        auth true

        def exec(_), do: :ok
      end

      actions [DefAuth, NoAuth, WithAuth]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "authentication is enforced by default" do
    conn = call_action(Auth, "myresource", "defauth")

    assert conn.status == 400
    assert conn.resp_body["status"] === false
  end

  test "authentication enforcing can be disabled" do
    conn = call_action(Auth, "myresource", "noauth")

    assert conn.status == 200
    assert conn.resp_body["status"] === true
  end

  test "authentication enforcing can be explicitly enabled" do
    conn = call_action(Auth, "myresource", "withauth")

    assert conn.status == 400
    assert conn.resp_body["status"] === false
  end
end
