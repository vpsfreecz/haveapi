defmodule HaveAPI.Validator.PresenceTest do
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

      defmodule PresenceNone do
        use Template

        input do
          string :str
        end

        def exec(_req), do: :ok
      end

      defmodule PresenceOn do
        use Template

        input do
          string :str, validate: [
            required: true
          ]
        end

        def exec(_req), do: :ok
      end

      defmodule PresenceOff do
        use Template

        input do
          string :str, validate: [
            required: false
          ]
        end

        def exec(_req), do: :ok
      end

      defmodule PresenceEmpty do
        use Template

        input do
          string :str, validate: [
            required: [empty: true]
          ]
        end

        def exec(_req), do: :ok
      end

      defmodule PresenceMessage do
        use Template

        input do
          string :str, validate: [
            required: [message: "presence test"]
          ]
        end

        def exec(_req), do: :ok
      end

      defmodule PresenceTypes do
        use Template

        input do
          boolean :boolean, validate: [required: true]
          integer :integer, validate: [required: true]
          float :float, validate: [required: true]
          datetime :datetime, validate: [required: true]
          custom :custom, validate: [required: true]
        end

        def exec(_req), do: :ok
      end

      actions [
        PresenceNone,
        PresenceOn,
        PresenceOff,
        PresenceEmpty,
        PresenceMessage,
        PresenceTypes,
      ]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "is disabled by default" do
    conn = call_action(Api, "myresource", "presencenone")

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "can be enabled by required: true" do
    conn = call_action(Api, "myresource", "presenceon")

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end

  test "does not accept empty string by default" do
    conn = call_action(Api, "myresource", "presenceon", input: %{str: "  \n  "})

    assert conn.status === 400
    assert conn.resp_body["status"] === false

    conn = call_action(Api, "myresource", "presenceon", input: %{str: "test"})

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "can be disabled by required: false" do
    conn = call_action(Api, "myresource", "presenceoff")

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "can accept empty values when empty: true" do
    conn = call_action(Api, "myresource", "presenceempty", input: %{str: ""})

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "checks presence when empty: true" do
    conn = call_action(Api, "myresource", "presenceempty")

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end

  test "can set custom error message" do
    conn = call_action(Api, "myresource", "presencemessage")

    assert conn.status === 400
    assert conn.resp_body["status"] === false
    assert List.first(conn.resp_body["errors"]["str"]) == "presence test"
  end

  test "works with all data types" do
    conn = call_action(Api, "myresource", "presencetypes")

    assert conn.status === 400
    assert conn.resp_body["status"] === false

    conn = call_action(Api, "myresource", "presencetypes", input: %{
      boolean: false,
      integer: 0,
      float: 0.5,
      datetime: "2017-08-10T00:00:30Z",
      custom: ~w(one two three)
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end
end
