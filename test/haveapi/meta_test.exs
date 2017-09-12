defmodule HaveAPI.MetaTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule MetaTemplate do
        use HaveAPI.Action

        meta :global do
          input do
            string :global_in_str
          end

          output do
            string :global_out_str
          end
        end

        meta :local do
          output do
            string :local_out_str
          end
        end
      end

      defmodule InheritedMeta do
        use MetaTemplate

        auth false
        method :get
        route "%{action}"

        output do
          string :global_in_str
        end

        def exec(req) do
          {
            :ok,
            %{global_in_str: req.meta.global_in_str, _meta: %{local_out_str: "local_test"}},
            %{global_out_str: "global_test"}
          }
        end
      end

      actions [InheritedMeta]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  test "meta parameters can be inherited from templates" do
    conn = call_api(Api, :get, "/myresource/inheritedmeta", "_meta", %{global_in_str: "test"})

    assert conn.status == 200
    assert conn.resp_body["status"] === true
    assert conn.resp_body["response"]["_meta"]["global_out_str"] == "global_test"
    assert conn.resp_body["response"]["myresource"]["global_in_str"] == "test"
    assert conn.resp_body["response"]["myresource"]["_meta"]["local_out_str"] == "local_test"
  end
end
