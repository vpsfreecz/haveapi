defmodule HaveAPI.Action.Update do
  use HaveAPI.Action

  method :put
  route "/:%{resource}_id"
end
