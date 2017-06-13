defmodule HaveAPI.Action.Index do
  use HaveAPI.Action

  method :get
  route "/"

  input do
    integer :limit
    integer :offset
  end
end
