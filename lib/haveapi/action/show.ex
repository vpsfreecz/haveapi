defmodule HaveAPI.Action.Show do
  use HaveAPI.Action

  method :get
  route "/:%{resource}_id"

  meta :local do
    output do
      custom :url_params
      boolean :resolved
    end
  end

  post_exec :add_local_metadata

  # TODO: mention/fix that we need output parameter `id` to be present
  def add_local_metadata(req, res) do
    if res.output[:id] do
      %{res | output: Map.put(res.output, :_meta, %{
          url_params: (req.params |> Keyword.delete_first(:glob) |> Keyword.values) ++ [res.output.id],
          resolved: true
      })}

    else
      res
    end
  end
end
