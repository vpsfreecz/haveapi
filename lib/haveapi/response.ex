defmodule HaveAPI.Response do
  defstruct [:context, :conn, :status, :output, :message, :errors]
end
