defmodule HaveAPI.Validator.ParametersTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Default do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        defmodule Params do
          use HaveAPI.Parameters

          string :str
          string :str_default, default: "test"
          string :str_fill, default: "test", fill: true
          string :str_none, fill: true
        end

        input do
          use Params
        end

        output do
          use Params
        end

        def exec(req), do: req.input
      end

      actions [Default]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  describe "parameter default value" do
    test "is in description when set" do
      conn = call_api(Api, :options, "/v1.0/myresource/default/method=post")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert Map.has_key?(conn.resp_body["response"]["input"]["parameters"]["str_default"], "default")
      assert conn.resp_body["response"]["input"]["parameters"]["str_default"]["default"] == "test"
    end

    test "is not in description when not set" do
      conn = call_api(Api, :options, "/v1.0/myresource/default/method=post")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      refute Map.has_key?(conn.resp_body["response"]["input"]["parameters"]["str"], "default")
    end

    test "has no default implicitly" do
      conn = call_action(Api, "myresource", "default")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      refute Map.has_key?(conn.resp_body["response"]["myresource"], "str")
    end

    test "can be set but not filled" do
      conn = call_action(Api, "myresource", "default")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      refute Map.has_key?(conn.resp_body["response"]["myresource"], "str_default")
    end

    test "can be set and filled" do
      conn = call_action(Api, "myresource", "default")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert Map.has_key?(conn.resp_body["response"]["myresource"], "str_fill")
      assert conn.resp_body["response"]["myresource"]["str_fill"] == "test"
    end

    test "fill: true has no effect when default is not set" do
      conn = call_action(Api, "myresource", "default")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      refute Map.has_key?(conn.resp_body["response"]["myresource"], "str_none")
    end
  end
end
