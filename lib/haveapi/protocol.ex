defmodule HaveAPI.Protocol do
  def read() do
    
  end

  def send(status, opts) do
    Poison.encode!(%{
      status: status,
      response: opts[:response] || nil,
      message: opts[:message] || nil,
      errors: opts[:errors] || nil,
    })
  end
end
