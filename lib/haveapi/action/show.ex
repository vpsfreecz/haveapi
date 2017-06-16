defmodule HaveAPI.Action.Show do
  use HaveAPI.Action

  method :get
  route "/:%{resource}_id"
end
