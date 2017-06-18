defmodule HaveAPI.ActionTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule PathParameters do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Show do
        use HaveAPI.Action.Show
      end

      defmodule Custom do
        use HaveAPI.Action

        method :post
        route ":%{resource}_id/%{action}"
      end

      actions [Show, Custom]

      defmodule SubResource do
        use HaveAPI.Resource

        resource_route ":%{resource}_id/%{resource}"

        defmodule Show do
          use HaveAPI.Action.Show
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
    conn = call_api(PathParameters, :options, "/myresource/$id/method=get")
    assert conn.resp_body["response"]["url"] == "/myresource/:myresource_id"

    conn = call_api(PathParameters, :options, "/myresource/$id/custom/method=post")
    assert conn.resp_body["response"]["url"] == "/myresource/:myresource_id/custom"

    conn = call_api(PathParameters, :options, "/myresource/$id/subresource/$id/method=get")
    assert conn.resp_body["response"]["url"] == "/myresource/:myresource_id/subresource/:subresource_id"
  end
end
