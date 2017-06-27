defmodule HaveAPI.ValidatorTest do
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

      defmodule PresenceOn do
        use Template

        input do
          string :str, validate: [
            required: true
          ]
        end

        def exec(_req), do: :ok
      end

      actions [
        PresenceOn,
      ]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "validators are in action description" do
    conn = call_api(Api, :options, "/v1.0/myresource/presenceon/method=post")

    assert conn.status === 200
    assert get_in(
      conn.resp_body,
      ~w(response
        input
        parameters
        str
        validators
        presence)) |> is_map
  end
end
