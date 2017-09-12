defmodule HaveAPI.ActionTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Params do
        use HaveAPI.Parameters

        integer :id
        string :label
      end

      defmodule Show do
        use HaveAPI.Action.Show

        auth false

        def find(_req), do: :ok
      end

      defmodule Custom do
        use HaveAPI.Action

        method :post
        route ":%{resource}_id/%{action}"
        auth false
      end

      defmodule NilNoOutput do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        def exec(_req), do: nil
      end

      defmodule OkNoOutput do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        def exec(_req), do: :ok
      end

      defmodule NilHash do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        output do: use Params

        def exec(_req), do: nil
      end

      defmodule DataHash do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        output do: use Params

        def exec(_req), do: %{id: 1, label: "test"}
      end

      defmodule OkDataHash do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        output do: use Params

        def exec(_req), do: {:ok, %{id: 1, label: "test"}}
      end

      defmodule MetaDataHash do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        output do: use Params

        meta :global do
          output do: string :meta_str
        end

        def exec(_req), do: {:ok, %{id: 1, label: "test"}, %{meta_str: "test"}}
      end

      defmodule ErrorMsgHash do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        output do: use Params

        def exec(_req), do: {:error, "serious error"}
      end

      defmodule ErrorParamsHash do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        input do: string :str
        output do: use Params

        def exec(_req), do: {:error, "serious error", errors: %{str: ["custom error"]}}
      end

      defmodule ErrorStatusHash do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        output do: use Params

        def exec(_req), do: {:error, "serious error", http_status: 523}
      end

      defmodule InvalidReturn do
        use HaveAPI.Action

        method :post
        route "%{action}"
        auth false

        output do: use Params

        def exec(_req), do: :whatever
      end

      actions [
        Show,
        Custom,
        NilNoOutput,
        OkNoOutput,
        NilHash,
        DataHash,
        OkDataHash,
        MetaDataHash,
        ErrorMsgHash,
        ErrorParamsHash,
        ErrorStatusHash,
        InvalidReturn,
      ]

      defmodule SubResource do
        use HaveAPI.Resource

        resource_route ":%{resource}_id/%{resource}"

        defmodule Show do
          use HaveAPI.Action.Show

          auth false

          def find(_req), do: :ok
        end

        actions [Show]
      end

      resources [SubResource]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "path parameters are named after current resource" do
    conn = call_api(Api, :options, "/myresource/$id/method=get")
    assert conn.resp_body["response"]["url"] == "/myresource/:myresource_id"

    conn = call_api(Api, :options, "/myresource/$id/custom/method=post")
    assert conn.resp_body["response"]["url"] == "/myresource/:myresource_id/custom"

    conn = call_api(Api, :options, "/myresource/$id/subresource/$id/method=get")
    assert conn.resp_body["response"]["url"] == "/myresource/:myresource_id/subresource/:subresource_id"
  end

  describe "Action.exec" do
    test "replies with error on nil with no output" do
      conn = call_action(Api, "myresource", "nilnooutput")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
    end

    test "replies on :ok with no output" do
      conn = call_action(Api, "myresource", "oknooutput")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
    end

    test "replies with error on nil with configured output" do
      conn = call_action(Api, "myresource", "nilhash")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
    end

    test "can return data" do
      conn = call_action(Api, "myresource", "datahash")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["id"] == 1
    end

    test "can return data in a tuple" do
      conn = call_action(Api, "myresource", "okdatahash")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["id"] == 1
    end

    test "can return data in a tuple with global metadata" do
      conn = call_action(Api, "myresource", "metadatahash")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["id"] == 1
      assert conn.resp_body["response"]["_meta"]["meta_str"] == "test"
    end

    test "can return error message" do
      conn = call_action(Api, "myresource", "errormsghash")

      assert conn.status === 400
      assert conn.resp_body["status"] === false
      assert conn.resp_body["message"] == "serious error"
    end

    test "can return parameter errors" do
      conn = call_action(Api, "myresource", "errorparamshash")

      assert conn.status === 400
      assert conn.resp_body["status"] === false
      assert conn.resp_body["message"] == "serious error"
      assert is_map(conn.resp_body["errors"])
      assert is_list(conn.resp_body["errors"]["str"])
      assert List.first(conn.resp_body["errors"]["str"]) == "custom error"
    end

    test "can set error HTTP status code" do
      conn = call_action(Api, "myresource", "errorstatushash")

      assert conn.status === 523
      assert conn.resp_body["status"] === false
      assert conn.resp_body["message"] == "serious error"
    end

    test "replies with server error on invalid return value" do
      conn = call_action(Api, "myresource", "invalidreturn")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
    end
  end
end
