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

  def send_doc(doc) do
    Poison.encode!(%{
      version: "1.2",
      status: true,
      response: doc,
      message: nil,
      errors: nil,
    })
  end
end
