defmodule HaveAPI.ResourceTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Associations do
    use HaveAPI.Builder

    defmodule TopResource do
      use HaveAPI.Resource

      defmodule Show do
        use HaveAPI.Action.Show

        auth false

        output do
          integer :id
          string :str
        end

        def exec(req) do
          %{
            id: req.params[:topresource_id],
            str: "top-level #{req.params[:topresource_id]}"
          }
        end
      end

      actions [Show]

      defmodule NestedResource do
        use HaveAPI.Resource

        resource_route ":%{resource}_id/%{resource}"

        defmodule Show do
          use HaveAPI.Action.Show

          auth false

          output do
            integer :nested_id
          end

          def exec(req) do
            IO.puts "nestedresource.show"
            IO.inspect req.params
            %{nested_id: req.params[:nestedresource_id]}
          end
        end

        actions [Show]
      end
    end

    defmodule OneAssoc do
      use HaveAPI.Resource

      defmodule Index do
        use HaveAPI.Action.Index

        auth false

        output do
          resource [TopResource]
        end

        def exec(_req), do: for n <- 1..10, do: %{topresource: [n]}
      end

      defmodule Show do
        use HaveAPI.Action.Show

        auth false

        output do
          resource [TopResource]
        end

        def exec(_req), do: %{topresource: [10]}
      end

      actions [Index, Show]
    end

    defmodule SecondAssoc do
      use HaveAPI.Resource

      defmodule Show do
        use HaveAPI.Action.Show

        auth false

        output do
          resource [TopResource, TopResource.NestedResource]
        end

        def exec(_req), do: %{nestedresource: [10,20]}
      end

      actions [Show]
    end

    version "1.0" do
      resources [TopResource, OneAssoc, SecondAssoc]
    end

    mount "/"
  end

  test "supports output associations of top-level resources" do
    conn = call_action(Associations, "oneassoc", "show", params: [10])

    assert conn.status == 200
    assert conn.resp_body["response"]["oneassoc"]["topresource"]["id"] == 10

    conn = call_action(Associations, "oneassoc", "index")

    assert conn.status == 200
    assert length(conn.resp_body["response"]["oneassoc"]) == 10
    assert List.first(conn.resp_body["response"]["oneassoc"])["topresource"]["id"] == 1
  end

  test "supports output associations of nested resources" do
    conn = call_action(Associations, "secondassoc", "show", params: [10])

    assert conn.status == 200
    assert conn.resp_body["response"]["secondassoc"]["nestedresource"]["nested_id"] == 20
  end
end
