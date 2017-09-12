defmodule HaveAPI.Validator.LengthTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Template do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"
      end

      defmodule Equal do
        use Template

        input do
          string :str, validate: [length: 5]
        end

        def exec(_req), do: :ok
      end

      defmodule Min do
        use Template

        input do
          string :str, validate: [length: [min: 3]]
        end

        def exec(_req), do: :ok
      end

      defmodule Max do
        use Template

        input do
          string :str, validate: [length: [max: 5]]
        end

        def exec(_req), do: :ok
      end

      defmodule Interval do
        use Template

        input do
          string :str, validate: [length: 3..6]
        end

        def exec(_req), do: :ok
      end

      actions [Equal, Min, Max, Interval]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "accepts equal length" do
    conn = call_action(Api, "myresource", "equal", input: %{
      str: "12345",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "rejects wrong equal length" do
    conn = call_action(Api, "myresource", "equal", input: %{
      str: "123",
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end

  test "accepts minimal length (inclusive)" do
    conn = call_action(Api, "myresource", "min", input: %{
      str: "123",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true

    conn = call_action(Api, "myresource", "min", input: %{
      str: "1234",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "rejects incorrect minimal length (inclusive)" do
    conn = call_action(Api, "myresource", "min", input: %{
      str: "12",
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end

  test "accepts maximal length (inclusive)" do
    conn = call_action(Api, "myresource", "max", input: %{
      str: "12345",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true

    conn = call_action(Api, "myresource", "max", input: %{
      str: "1234",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "rejects incorrect maximal length (inclusive)" do
    conn = call_action(Api, "myresource", "max", input: %{
      str: "123456",
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end

  test "accepts length from interval (inclusive)" do
    conn = call_action(Api, "myresource", "interval", input: %{
      str: "123",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true

    conn = call_action(Api, "myresource", "interval", input: %{
      str: "123456",
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "rejects incorrect length from interval (inclusive)" do
    conn = call_action(Api, "myresource", "interval", input: %{
      str: "12",
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false

    conn = call_action(Api, "myresource", "interval", input: %{
      str: "1234567",
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end
end
