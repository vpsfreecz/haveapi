defmodule HaveAPI.Validator.NumericalityTest do
  use ExUnit.Case
  use HaveAPI.Test

  defmodule Api do
    use HaveAPI.Builder

    defmodule MyResource do
      use HaveAPI.Resource

      defmodule Template do
        use HaveAPI.Action

        auth false
        method :post
        route "%{action}"
      end

      defmodule Multi do
        use Template

        input do
          integer :int, validate: [number: [
            min: 2,
            max: 10,
            even: true,
            step: 2,
            mod: 2,
          ]]
        end

        def exec(_req), do: :ok
      end

      defmodule Min do
        use Template

        input do
          integer :int, validate: [number: [min: 3]]
        end

        def exec(_req), do: :ok
      end

      defmodule Max do
        use Template

        input do
          integer :int, validate: [number: [max: 5]]
        end

        def exec(_req), do: :ok
      end

      defmodule Interval do
        use Template

        input do
          integer :int, validate: [number: 3..6]
        end

        def exec(_req), do: :ok
      end

      defmodule Even do
        use Template

        input do
          integer :int, validate: [number: :even]
        end

        def exec(_req), do: :ok
      end

      defmodule Odd do
        use Template

        input do
          integer :int, validate: [number: :odd]
        end

        def exec(_req), do: :ok
      end

      defmodule StepZero do
        use Template

        input do
          integer :int, validate: [number: [step: 3]]
        end

        def exec(_req), do: :ok
      end

      defmodule StepMin do
        use Template

        input do
          integer :int, validate: [number: [step: 3, min: 5]]
        end

        def exec(_req), do: :ok
      end

      defmodule Mod do
        use Template

        input do
          integer :int, validate: [number: [mod: 5]]
        end

        def exec(_req), do: :ok
      end

      actions [Multi, Min, Max, Interval, Even, Odd, StepZero, StepMin, Mod]
    end

    version "1.0" do
      resources [MyResource]
    end

    mount "/"
  end

  describe "description" do
    test "is described correctly" do
      conn = call_api(Api, :options, "/v1.0/myresource/multi/method=post")

      validators = get_in(conn.resp_body, ~w(response input parameters int validators))

      assert Map.has_key?(validators, "number")
      assert validators["number"]["min"] === 2
      assert validators["number"]["max"] === 10
      assert validators["number"]["step"] === 2
      assert validators["number"]["mod"] === 2
      assert validators["number"]["even"] === true
    end
  end

  describe "min" do
    test "accepts minimal number (inclusive)" do
      for x <- [3,4] do
        conn = call_action(Api, "myresource", "min", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects incorrect minimal number (inclusive)" do
      conn = call_action(Api, "myresource", "min", input: %{
        int: 2,
      })

      assert conn.status === 400
      assert conn.resp_body["status"] === false
    end
  end

  describe "max" do
    test "accepts maximal number (inclusive)" do
      for x <- [4,5] do
        conn = call_action(Api, "myresource", "max", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects incorrect maximal number (inclusive)" do
      conn = call_action(Api, "myresource", "max", input: %{
        int: 6,
      })

      assert conn.status === 400
      assert conn.resp_body["status"] === false
    end
  end

  describe "interval" do
    test "accepts number from interval (inclusive)" do
      for x <- [3,6] do
        conn = call_action(Api, "myresource", "interval", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects number not from interval (inclusive)" do
      for x <- [2,7] do
        conn = call_action(Api, "myresource", "interval", input: %{
          int: x,
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
      end
    end
  end

  describe "even" do
    test "accepts even number" do
      for x <- [0,2,4,6,8,10] do
        conn = call_action(Api, "myresource", "even", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects odd number" do
      for x <- [1,3,5,7,9,11] do
        conn = call_action(Api, "myresource", "even", input: %{
          int: x,
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
      end
    end
  end

  describe "odd" do
    test "accepts odd number" do
      for x <- [1,3,5,7,9,11] do
        conn = call_action(Api, "myresource", "odd", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects even number" do
      for x <- [0,2,4,6,8,10] do
        conn = call_action(Api, "myresource", "odd", input: %{
          int: x,
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
      end
    end
  end

  describe "step" do
    test "accepts number in step from zero" do
      for x <- [-6,-3,0,3,9,12] do
        conn = call_action(Api, "myresource", "stepzero", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects number not in step from zero" do
      for x <- [-4,-1,1,2,4,8,10] do
        conn = call_action(Api, "myresource", "stepzero", input: %{
          int: x,
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
      end
    end

    test "accepts number in step from min" do
      for x <- [5,8,11,14,17] do
        conn = call_action(Api, "myresource", "stepmin", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects number not in step from min" do
      for x <- [-3,0,3,4,6,7,10] do
        conn = call_action(Api, "myresource", "stepmin", input: %{
          int: x,
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
      end
    end
  end

  describe "mod" do
    test "accepts numbers whose remainder is zero" do
      for x <- [-10,-5,0,5,10,15,20] do
        conn = call_action(Api, "myresource", "mod", input: %{
          int: x,
        })

        assert conn.status === 200
        assert conn.resp_body["status"] === true
      end
    end

    test "rejects numbers whose remainder is not zero" do
      for x <- [-12,-6,-4,1,4,6,11] do
        conn = call_action(Api, "myresource", "mod", input: %{
          int: x,
        })

        assert conn.status === 400
        assert conn.resp_body["status"] === false
      end
    end
  end
end
