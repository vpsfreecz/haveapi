defmodule HaveAPI.Validator.FormatTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule MatchFormat do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :str, validate: [format: ~r/^a/]
        end

        def exec(_req), do: :ok
      end

      defmodule NotMatchFormat do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :str, validate: [format: [rx: ~r/^a/, match: false]]
        end

        def exec(_req), do: :ok
      end

      actions [MatchFormat, NotMatchFormat]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "match: true accepts matching value" do
    conn = call_action(Api, "myresource", "matchformat", input: %{
      str: "atest"
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end

  test "match: true rejects not matching value" do
    conn = call_action(Api, "myresource", "matchformat", input: %{
      str: "test"
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end

  test "match: false rejects matching value" do
    conn = call_action(Api, "myresource", "notmatchformat", input: %{
      str: "atest"
    })

    assert conn.status === 400
    assert conn.resp_body["status"] === false
  end

  test "match: false accepts not matching value" do
    conn = call_action(Api, "myresource", "notmatchformat", input: %{
      str: "test"
    })

    assert conn.status === 200
    assert conn.resp_body["status"] === true
  end
end
