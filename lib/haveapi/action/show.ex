defmodule HaveAPI.Action.Show do
  use HaveAPI.Action

  @callback item(map) :: any

  method :get
  route "/:%{resource}_id"

  meta :local do
    output do
      custom :url_params
      boolean :resolved
    end
  end

  def use_template do
    quote do
      @behaviour unquote(__MODULE__)

      def exec(req) do
        unquote(__MODULE__).exec(__MODULE__, req)
      end
    end
  end

  def exec(mod, req) do
    v = mod.item(req)

    case v do
      nil ->
        {:error, "Object not found", http_status: 404}

      other ->
        res = HaveAPI.Action.Output.build(req, other)

        if res.status do
          add_local_metadata(req, res)

        else
          res
        end
    end
  end

  def add_local_metadata(req, res) do
    if res.output[:id] do
      %{res | output: Map.put(res.output, :_meta, %{
          url_params: (req.params |> Keyword.delete_first(:glob) |> Keyword.values),
          resolved: true
      })}

    else
      res
    end
  end
end
