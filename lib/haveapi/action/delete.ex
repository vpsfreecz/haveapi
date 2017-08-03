defmodule HaveAPI.Action.Delete do
  use HaveAPI.Action

  method :delete
  route "/:%{resource}_id"
  aliases [:destroy]
end
