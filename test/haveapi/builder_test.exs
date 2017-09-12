defmodule HaveAPI.BuilderTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule SingleVersion do
    use HaveAPI.Builder

    version "1.0" do

    end

    mount "/"
  end

  defmodule MultiVersion do
    use HaveAPI.Builder

    version "1.0" do

    end

    version "2.0" do

    end

    mount "/"
  end

  defmodule MultiVersionDefault do
    use HaveAPI.Builder

    version "1.0" do

    end

    version "2.0" do

    end

    default "2.0"
    mount "/"
  end

  defmodule WithResources do
    use HaveAPI.Builder

    defmodule MyResource do
      defmodule Index do
        use HaveAPI.Action.Index

        auth false

        output do
          string :test
        end

        def items(_req) do
          [%{test: "hello"}, %{test: "world"}]
        end

        def count(_req), do: 2
      end

      defmodule Show do
        use HaveAPI.Action.Show

        auth false

        output do
          string :test
        end

        def find(_req) do
          %{test: "hello"}
        end
      end

      defmodule Custom do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        input do
          string :str
        end

        output do
          string :str
        end

        def exec(req) do
          req.input
        end
      end

      use HaveAPI.Resource
      actions [Index, Show, Custom]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "builds single version API" do
    conn = call_api(SingleVersion, :options, "/?describe=versions")

    assert conn.status == 200
    assert conn.resp_body["response"]["versions"] == ["1.0"]
    assert conn.resp_body["response"]["default"] == "1.0"
  end

  test "builds multi version API" do
    conn = call_api(MultiVersion, :options, "/?describe=versions")

    assert conn.status == 200
    assert conn.resp_body["response"]["versions"] == ["1.0", "2.0"]
    assert conn.resp_body["response"]["default"] == "1.0"
  end

  test "configurable default version" do
    conn = call_api(MultiVersionDefault, :options, "/?describe=versions")

    assert conn.status == 200
    assert conn.resp_body["response"]["versions"] == ["1.0", "2.0"]
    assert conn.resp_body["response"]["default"] == "2.0"
  end

  test "sends complete doc" do
    conn = call_api(MultiVersion, :options, "/")

    assert conn.status == 200
    assert Map.keys(conn.resp_body["response"]["versions"]) == ["1.0", "2.0"]
  end

  test "sends per-version doc" do
    Enum.each(["1.0", "2.0"], fn v ->
      conn = call_api(MultiVersion, :options, "/v#{v}")
      assert conn.status == 200
    end)
  end

  test "responds on invalid version doc" do
    conn = call_api(MultiVersion, :options, "/vnope")

    assert conn.status == 404
    assert conn.resp_body["status"] === false
  end

  test "responds on per-action doc" do
    Enum.each(["/myresource/method=get", "/v1.0/myresource/method=get"], fn path ->
      conn = call_api(WithResources, :options, path)

      assert conn.status == 200
    end)
  end

  test "executes action" do
    conn = call_action(WithResources, "myresource", "index")
    assert conn.status == 200
    assert is_list(conn.resp_body["response"]["myresource"])

    conn = call_action(WithResources, "myresource", "show", params: [5])

    assert conn.status == 200
    assert is_map(conn.resp_body["response"]["myresource"])

    conn = call_action(WithResources, "myresource", "custom", input: %{str: "hey"})

    assert conn.status == 200
    assert conn.resp_body["response"]["myresource"]["str"] == "hey"
  end

  test "responds on invalid action" do
    conn = call_api(MultiVersion, :get, "/whatever")

    assert conn.status == 404
    assert conn.resp_body["status"] === false

    conn = call_api(MultiVersion, :post, "/v1.0/whatever")

    assert conn.status == 404
    assert conn.resp_body["status"] === false
  end
end
