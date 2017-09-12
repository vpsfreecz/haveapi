defmodule HaveAPI.Action.Index do
  use HaveAPI.Action

  @callback items(map) :: any
  @callback count(map) :: integer

  method :get
  route "/"
  aliases [:list]

  input do
    integer :limit
    integer :offset
  end

  output :object_list do

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

  def use_template do
    quote do
      @behaviour unquote(__MODULE__)

      def exec(req) do
        unquote(__MODULE__).exec(__MODULE__, req)
      end
    end
  end

  def exec(mod, req) do
    res = HaveAPI.Action.Output.build(req, mod.items(req))

    if res.status do
      res = add_total_count(mod, req, res)
      add_local_metadata(mod, req, res)

    else
      res
    end
  end

  def add_total_count(mod, req, res) do
    if req.meta && req.meta[:total_count] do
      if res.meta do
        put_in(res.meta[:total_count], mod.count(req))

      else
        %{res | meta: %{total_count: mod.count(req)}}
      end

    else
      res
    end
  end

  # TODO: mention/fix that we need output parameter `id` to be present
  def add_local_metadata(mod, req, res) do
    if Enum.find(mod.params(:output), &(&1.name == :id)) do
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
