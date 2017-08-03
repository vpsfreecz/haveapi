defmodule HaveAPI.Action.Create do
  use HaveAPI.Action

  @callback create(map) :: any

  method :post
  route ""
  aliases [:new]

  meta :global do
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
    v = mod.create(req)
    res = HaveAPI.Action.Output.build(req, v)

    if res.status do
      add_local_metadata(req, res)

    else
      res
    end
  end

  # TODO: mention/fix that we need output parameter `id` to be present
  def add_local_metadata(req, res) do
    if res.output[:id] do
      %{res | meta: %{
          url_params: (
            req.params |> Keyword.delete_first(:glob) |> Keyword.values
          ) ++ [res.output[:id]],
          resolved: true
      }}

    else
      res
    end
  end
end
