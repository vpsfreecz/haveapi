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

  post_exec :add_total_count

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
end
