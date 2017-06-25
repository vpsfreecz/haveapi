defmodule HaveAPI.Action.Index do
  use HaveAPI.Action

  method :get
  route "/"

  input do
    integer :limit
    integer :offset
  end

  output :hash_list do

  end

  meta :global do
    input do
      boolean :total_count
    end

    output do
      integer :total_count
    end
  end

  meta :local do
    output do
      custom :url_params
      boolean :resolved
    end
  end

  post_exec :add_total_count
  post_exec :add_local_metadata

  def add_total_count(req, res) do
    if req.meta && req.meta.total_count do
      if res.meta do
        put_in(res.meta[:total_count], req.context.action.count(req))

      else
        %{res | meta: %{total_count: req.context.action.count(req)}}
      end

    else
      res
    end
  end

  # TODO: mention/fix that we need output parameter `id` to be present
  def add_local_metadata(req, res) do
    if Enum.find(res.context.action.params(:output), &(&1.name == :id)) do
      %{res | output: Enum.map(res.output, fn item ->
        Map.put(item, :_meta, %{
          url_params: (req.params |> Keyword.delete_first(:glob) |> Keyword.values) ++ [item.id],
          resolved: true
        })
      end)}

    else
      res
    end
  end
end
