defmodule HaveAPI.Validator.InclusionTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule IncludeList do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :string, validate: [
            include: [values: ~w(one two three)]
          ]
          integer :integer, validate: [
            include: [values: [1,2,3]]
          ]
          float :float, validate: [
            include: [values: [1.1, 1.2, 1.3]]
          ]
          boolean :boolean, validate: [
            include: [values: [true]]
          ]
          datetime :datetime, validate: [
            include: [values: [
              ({:ok, dt, _offset} = DateTime.from_iso8601("2017-08-10T11:23:00Z")) |> elem(1)
            ]]
          ]
          custom :custom, validate: [
            include: [values: [%{"test" => 123}]]
          ]
        end

        def exec(_req), do: :ok
      end

      defmodule IncludeHash do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          {:ok, dt, _offset} = DateTime.from_iso8601("2017-08-10T11:23:00Z")

          string :string, validate: [
            include: [values: %{"one" => "One", "two" => "Two"}]
          ]
          integer :integer, validate: [
            include: [values: %{1 => "One", 2 => "Two"}]
          ]
          float :float, validate: [
            include: [values: %{1.1 => "One point one", 1.2 => "One point two"}]
          ]
          boolean :boolean, validate: [
            include: [values: %{true => "True"}]
          ]
          datetime :datetime, validate: [
            include: [values: %{dt => "Some day"}]
          ]
          custom :custom, validate: [
            include: [values: %{%{"test" => 123} => "Very map"}]
          ]
        end

        def exec(_req), do: :ok
      end

      actions [IncludeList, IncludeHash]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  for action <- ~w(includelist includehash) do
    describe action do
      test "accepts configured value" do
        conn = call_action(Api, "myresource", unquote(action), input: %{
          string: "two",
          integer: 2,
          float: 1.1,
          boolean: true,
          datetime: "2017-08-10T11:23:00Z",
          custom: %{"test" => 123}
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end

      test "rejects incorrect value from list" do
        conn = call_action(Api, "myresource", unquote(action), input: %{
          string: "test",
          integer: 12356,
          float: 5.9,
          boolean: false,
          datetime: "2018-08-10T11:23:00Z",
          custom: %{"test" => 12356}
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
        assert (conn.resp_body["errors"] |> Map.keys |> length) === 6
      end
    end
  end

  test "error message includes value" do
    conn = call_action(Api, "myresource", "includelist", input: %{
      string: "ten"
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
    assert (conn.resp_body["errors"]["string"] |> List.first) === ~s("ten" cannot be used)
  end
end
