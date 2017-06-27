defmodule HaveAPI.Validator.ExclusionTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule ExcludeList do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :string, validate: [
            exclude: [values: ~w(one two three)]
          ]
          integer :integer, validate: [
            exclude: [values: [1,2,3]]
          ]
          float :float, validate: [
            exclude: [values: [1.1, 1.2, 1.3]]
          ]
          boolean :boolean, validate: [
            exclude: [values: [true]]
          ]
          datetime :datetime, validate: [
            exclude: [values: ["2017-08-10T11:23:00Z"]]
          ]
          custom :custom, validate: [
            exclude: [values: [%{"test" => 123}]]
          ]
        end

        def exec(_req), do: :ok
      end

      actions [ExcludeList]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "rejects configured values" do
    conn = call_action(Api, "myresource", "excludelist", input: %{
      string: "two",
      integer: 2,
      float: 1.1,
      boolean: true,
      datetime: "2017-08-10T11:23:00Z",
      custom: %{"test" => 123}
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
    assert (conn.resp_body["errors"] |> Map.keys |> length) === 6
  end

  test "accepts different values" do
    conn = call_action(Api, "myresource", "excludelist", input: %{
      string: "test",
      integer: 12356,
      float: 5.9,
      boolean: false,
      datetime: "2018-08-10T11:23:00Z",
      custom: %{"test" => 12356}
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end
end
