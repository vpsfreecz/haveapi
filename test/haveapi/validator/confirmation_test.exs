defmodule HaveAPI.Validator.ConfirmationTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule ConfirmEqual do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :str1
          string :str2, validate: [confirm: :str1]
        end

        def exec(_req), do: :ok
      end

      defmodule ConfirmNotEqual do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :str1
          string :str2, validate: [confirm: [parameter: :str1, equal: false]]
        end

        def exec(_req), do: :ok
      end

      actions [ConfirmEqual, ConfirmNotEqual]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "is inactive when parameters aren't present nor required" do
    conn = call_action(Api, "myresource", "confirmequal")

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "is not enforced when the second parameter is not present" do
    conn = call_action(Api, "myresource", "confirmequal", input: %{
      str1: "whatever",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "is enforced when both parameters are present" do
    conn = call_action(Api, "myresource", "confirmequal", input: %{
      str1: "test",
      str2: "whatever",
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
    assert Map.size(conn.resp_body["errors"]) == 1
    assert Map.has_key?(conn.resp_body["errors"], "str2")

    conn = call_action(Api, "myresource", "confirmequal", input: %{
      str1: "test",
      str2: "test",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "ensures parameters differ" do
    conn = call_action(Api, "myresource", "confirmnotequal", input: %{
      str1: "test",
      str2: "whatever",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true

    conn = call_action(Api, "myresource", "confirmnotequal", input: %{
      str1: "test",
      str2: "test",
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
    assert Map.size(conn.resp_body["errors"]) == 1
    assert Map.has_key?(conn.resp_body["errors"], "str2")
  end
end
