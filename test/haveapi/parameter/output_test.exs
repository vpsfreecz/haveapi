defmodule HaveAPI.Validator.ParameterOutputTest do
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

        def item(req), do: %{id: req.params[:association_id]}
      end
    end

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Template do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"
      end

      defmodule StringOk do
        use Template

        output do
          string :str1
          string :str2
          string :str3
          string :str4
        end

        def exec(_req), do: %{str1: "test", str2: 123, str3: 1.55, str4: true}
      end

      defmodule StringError do
        use Template

        output do
          string :str1
        end

        def exec(_req), do: %{str1: %{a: 1}}
      end

      defmodule TextOk do
        use Template

        output do
          string :str1
          string :str2
          string :str3
          string :str4
        end

        def exec(_req), do: %{str1: "test", str2: 123, str3: 1.55, str4: true}
      end

      defmodule TextError do
        use Template

        output do
          string :str1
        end

        def exec(_req), do: %{str1: %{a: 1}}
      end

      defmodule IntegerOk do
        use Template

        output do
          integer :int
        end

        def exec(_req), do: %{int: 123}
      end

      defmodule IntegerError do
        use Template

        output do
          integer :int1
          integer :int2
          integer :int3
          integer :int4
        end

        def exec(_req), do: %{int1: 1.5, int2: "123", int3: true, int4: %{}}
      end

      defmodule FloatOk do
        use Template

        output do
          float :flt
        end

        def exec(_req), do: %{flt: 5.65}
      end

      defmodule FloatError do
        use Template

        output do
          float :flt1
          float :flt2
          float :flt3
          float :flt4
        end

        def exec(_req), do: %{flt1: 15, flt2: "123", flt3: true, flt4: %{}}
      end

      defmodule BooleanOk do
        use Template

        output do
          boolean :bool
        end

        def exec(_req), do: %{bool: true}
      end

      defmodule BooleanError do
        use Template

        output do
          boolean :bool1
          boolean :bool2
          boolean :bool3
          boolean :bool4
        end

        def exec(_req), do: %{bool1: 15, bool2: "123", bool3: 5.5, bool4: %{}}
      end

      defmodule DatetimeOk do
        use Template

        output do
          datetime :d
          datetime :dt
        end

        def exec(_req) do
          {:ok, d} = Date.from_iso8601("2017-10-08")
          {:ok, dt, _offset} = DateTime.from_iso8601("2017-10-08T10:00:30Z")
          %{d: d, dt: dt}
        end
      end

      defmodule DatetimeError do
        use Template

        output do
          datetime :dt1
          datetime :dt2
          datetime :dt3
          datetime :dt4
          datetime :dt5
        end

        def exec(_req), do: %{dt1: 15, dt2: "123", dt3: 5.5, dt4: %{}, dt5: "2017-05-10"}
      end

      defmodule ListOk do
        use Template

        output :hash_list do
          integer :int
        end

        def exec(_req) do
          for x <- 1..10, do: %{int: x}
        end
      end

      defmodule ListError do
        use Template

        output :hash_list do
          integer :int
        end

        def exec(_req) do
          [
            %{int: 1},
            %{int: 2},
            %{int: "123"},
            %{int: 1.5},
            %{int: true},
            %{int: 3},
          ]
        end
      end

      actions [
        StringOk,
        StringError,

        TextOk,
        TextError,

        IntegerOk,
        IntegerError,

        FloatOk,
        FloatError,

        BooleanOk,
        BooleanError,

        DatetimeOk,
        DatetimeError,

        ListOk,
        ListError,
      ]
    end

    version "1.0" do
      resources [MyResource, Association]
    end

    mount "/"
  end

  describe "string coercion" do
    test "accepts values implementing String.Chars protocol" do
      conn = call_action(Api, "myresource", "stringok")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["str1"] === "test"
      assert conn.resp_body["response"]["myresource"]["str2"] === "123"
      assert conn.resp_body["response"]["myresource"]["str3"] === "1.55"
      assert conn.resp_body["response"]["myresource"]["str4"] === "true"
    end

    test "rejects values that do not implement String.Chars protocol" do
      conn = call_action(Api, "myresource", "stringerror")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
      assert Map.size(conn.resp_body["errors"]) == 1
    end
  end

  describe "text coercion" do
    test "accepts values implementing String.Chars protocol" do
      conn = call_action(Api, "myresource", "textok")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["str1"] === "test"
      assert conn.resp_body["response"]["myresource"]["str2"] === "123"
      assert conn.resp_body["response"]["myresource"]["str3"] === "1.55"
      assert conn.resp_body["response"]["myresource"]["str4"] === "true"
    end

    test "rejects values that do not implement String.Chars protocol" do
      conn = call_action(Api, "myresource", "texterror")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
      assert Map.size(conn.resp_body["errors"]) == 1
    end
  end

  describe "integer coercion" do
    test "accepts integers" do
      conn = call_action(Api, "myresource", "integerok")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["int"] === 123
    end

    test "rejects other values" do
      conn = call_action(Api, "myresource", "integererror")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
      assert Map.size(conn.resp_body["errors"]) == 4
    end
  end

  describe "float coercion" do
    test "accepts floats" do
      conn = call_action(Api, "myresource", "floatok")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["flt"] === 5.65
    end

    test "rejects other values" do
      conn = call_action(Api, "myresource", "floaterror")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
      assert Map.size(conn.resp_body["errors"]) == 4
    end
  end

  describe "boolean coercion" do
    test "accepts booleans" do
      conn = call_action(Api, "myresource", "booleanok")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["bool"] === true
    end

    test "rejects other values" do
      conn = call_action(Api, "myresource", "booleanerror")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
      assert Map.size(conn.resp_body["errors"]) == 4
    end
  end

  describe "datetime coercion" do
    test "accepts datetimes" do
      conn = call_action(Api, "myresource", "datetimeok")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert conn.resp_body["response"]["myresource"]["d"] === "2017-10-08"
      assert conn.resp_body["response"]["myresource"]["dt"] === "2017-10-08T10:00:30Z"
    end

    test "rejects other values" do
      conn = call_action(Api, "myresource", "datetimeerror")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
      assert Map.size(conn.resp_body["errors"]) == 5
    end
  end

  describe "lists" do
    test "accepts correct values" do
      conn = call_action(Api, "myresource", "listok")

      assert conn.status === 200
      assert conn.resp_body["status"] === true
      assert length(conn.resp_body["response"]["myresource"]) == 10
    end

    test "rejects incorrect values" do
      conn = call_action(Api, "myresource", "listerror")

      assert conn.status === 500
      assert conn.resp_body["status"] === false
      assert Map.has_key?(conn.resp_body["errors"], "int")
    end
  end
end
