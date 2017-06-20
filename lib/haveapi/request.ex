defmodule HaveAPI.Request do
  defstruct [:context, :conn, :params, :input, :meta, :user]
end
