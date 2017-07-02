defmodule HaveAPI.Validator.ParametersTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule Association do
      use HaveAPI.Resource

      defmodule Show do
        use HaveAPI.Action.Show

        auth false

        output do
          integer :id
        end

        def exec(req), do: %{id: req.params[:association_id]}
      end
    end

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Types do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"

        input do
          string :string
          text :text
          integer :integer
          float :float
          boolean :boolean
          datetime :datetime
          resource [Association]
          custom :custom
        end

        def exec(_req), do: :ok
      end

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

      actions [Types, Default]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  describe "string coercion" do
    test "accepts string" do
      conn = call_action(Api, "myresource", "types", input: %{
        string: "test"
      })

      assert conn.status === 200
      assert conn.resp_body["status"] === true
    end

    test "rejects invalid data" do
      for v <- [123, 5.5, true, false] do
        conn = call_action(Api, "myresource", "types", input: %{
          string: v
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
        assert Map.has_key?(conn.resp_body["errors"], "string")
      end
    end
  end

  describe "text coercion" do
    test "accepts string" do
      conn = call_action(Api, "myresource", "types", input: %{
        text: "test"
      })

      assert conn.status === 200
      assert conn.resp_body["status"] === true
    end

    test "rejects invalid data" do
      for v <- [123, 5.5, true, false] do
        conn = call_action(Api, "myresource", "types", input: %{
          text: v
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
        assert Map.has_key?(conn.resp_body["errors"], "text")
      end
    end
  end

  describe "integer coercion" do
    test "accepts integer" do
      conn = call_action(Api, "myresource", "types", input: %{
        integer: 123
      })

      assert conn.status === 200
      assert conn.resp_body["status"] === true
    end

    test "rejects invalid data" do
      for v <- ["123", 5.5, true, false] do
        conn = call_action(Api, "myresource", "types", input: %{
          integer: v
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
        assert Map.has_key?(conn.resp_body["errors"], "integer")
      end
    end
  end

  describe "float coercion" do
    test "accepts float" do
      conn = call_action(Api, "myresource", "types", input: %{
        float: 1.25
      })

      assert conn.status === 200
      assert conn.resp_body["status"] === true
    end

    test "rejects invalid data" do
      for v <- ["123", 55, true, false] do
        conn = call_action(Api, "myresource", "types", input: %{
          float: v
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
        assert Map.has_key?(conn.resp_body["errors"], "float")
      end
    end
  end

  describe "boolean coercion" do
    test "accepts boolean" do
      for v <- [true, false, "1", "0"] do
        conn = call_action(Api, "myresource", "types", input: %{
          boolean: v
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects invalid data" do
      for v <- [123, 5.5, "true", "false", "t", "f"] do
        conn = call_action(Api, "myresource", "types", input: %{
          boolean: v
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
        assert Map.has_key?(conn.resp_body["errors"], "boolean")
      end
    end
  end

  describe "datetime coercion" do
    test "accepts ISO 8601" do
      values = [
        Date.utc_today |> Date.to_iso8601,
        DateTime.utc_now |> DateTime.to_iso8601
      ]

      for v <- values do
        conn = call_action(Api, "myresource", "types", input: %{
          datetime: v
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects invalid data" do
      for v <- [123, 5.5, true, false, "test", "2017-13-15", "2017-13-32"] do
        conn = call_action(Api, "myresource", "types", input: %{
          datetime: v
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
        assert Map.has_key?(conn.resp_body["errors"], "datetime")
      end
    end
  end

  describe "resource coercion" do
    # TODO: it should accept identifiers of associated resources, not
    # everything
    test "accepts any value" do
      for v <- ["test", 123, 5.5, true, false] do
        conn = call_action(Api, "myresource", "types", input: %{
          resource: v
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end
  end

  describe "custom coercion" do
    test "accepts any value" do
      for v <- ["test", 123, 5.5, true, false, [1,2,3], %{a: 1, b: 2}] do
        conn = call_action(Api, "myresource", "types", input: %{
          custom: v
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end
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
