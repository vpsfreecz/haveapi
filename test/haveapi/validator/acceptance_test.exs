defmodule HaveAPI.Validator.AcceptanceTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Accept do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          {:ok, dt, _offset} = DateTime.from_iso8601("2017-08-10T11:23:00Z")

          string :string, validate: [accept: "test"]
          integer :integer, validate: [accept: 123]
          float :float, validate: [accept: 5.25]
          boolean :boolean, validate: [accept: false]
          datetime :datetime, validate: [accept: dt]
          custom :custom, validate: [accept: [value: %{"test" => 123}]]
        end

        def exec(_req), do: :ok
      end

      actions [Accept]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "accepts configured values" do
    conn = call_action(Api, "myresource", "accept", input: %{
      string: "test",
      integer: 123,
      float: 5.25,
      boolean: false,
      datetime: "2017-08-10T11:23:00Z",
      custom: %{"test" => 123}
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "rejects incorrect values" do
    conn = call_action(Api, "myresource", "accept", input: %{
      string: "test not",
      integer: 12356,
      float: 5.9,
      boolean: true,
      datetime: "2018-08-10T11:23:00Z",
      custom: %{"test" => 12356}
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
    assert (conn.resp_body["errors"] |> Map.keys |> length) === 6
  end
end
