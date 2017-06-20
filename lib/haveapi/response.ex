defmodule HaveAPI.Response do
  defstruct [:context, :conn, :status, :output, :meta, :message, :errors]
end
