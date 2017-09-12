defmodule HaveAPI.ProtocolTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule GlobalMeta do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        meta :global do
          output do
            string :str
          end
        end

        def exec(_req) do
          {:ok, nil, %{str: "test"}}
        end
      end

      defmodule NoGlobalMeta do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        meta :global do
          output do
            string :str
          end
        end

        def exec(_req), do: :ok
      end

      actions [
        GlobalMeta,
        NoGlobalMeta,
      ]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "global meta is present only if actually sent" do
    conn = call_action(Api, "myresource", "globalmeta")

    assert conn.status === 200
    assert conn.resp_body["status"] === true
    assert Map.has_key?(conn.resp_body["response"], "_meta")

    conn = call_action(Api, "myresource", "noglobalmeta")

    assert conn.status === 200
    assert conn.resp_body["status"] === true
    refute Map.has_key?(conn.resp_body["response"], "_meta")
  end
end
