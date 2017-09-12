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

      defmodule Patching do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :str1, label: "Something"
          patch :str1, label: "Else", description: "Useful", default: "123"

          string :str2, validate: [required: true]
          patch :str2, validate: [required: false]

          string :str3, validate: [required: true]
          patch :str3, validate: [format: ~r/.+/]

          string :str4, validate: [required: true]
          patch :str4, []

          string :str5, validate: [required: true]
          patch :str5, validate: []

          string :str6
          patch :str6, validate: [required: true]
        end

        def exec(_req), do: :ok
      end

      actions [Default, Patching]
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

  describe "parameter patching" do
    setup do
      conn = call_api(Api, :options, "/v1.0/myresource/patching/method=post")
      [params: conn.resp_body["response"]["input"]["parameters"]]
    end

    test "can add options", context do
      assert context[:params]["str1"]["label"] == "Else"
      assert context[:params]["str1"]["description"] == "Useful"
      assert context[:params]["str1"]["default"] == "123"
    end

    test "can remove presence validator", context do
      assert Enum.empty?(context[:params]["str2"]["validators"])
    end

    test "can add validators", context do
      assert Map.size(context[:params]["str3"]["validators"]) == 2
      assert Map.has_key?(context[:params]["str3"]["validators"], "present")
      assert Map.has_key?(context[:params]["str3"]["validators"], "format")
    end

    test "does not break validators when not specified", context do
      assert Map.size(context[:params]["str4"]["validators"]) == 1
      assert Map.has_key?(context[:params]["str4"]["validators"], "present")
    end

    test "does not break validators when specified as empty list", context do
      assert Map.size(context[:params]["str5"]["validators"]) == 1
      assert Map.has_key?(context[:params]["str5"]["validators"], "present")
    end

    test "can add new validators when previously not set", context do
      assert Map.size(context[:params]["str6"]["validators"]) == 1
      assert Map.has_key?(context[:params]["str6"]["validators"], "present")
    end
  end
end
