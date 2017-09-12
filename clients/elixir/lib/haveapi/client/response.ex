defmodule HaveAPI.Client.Response do
  defstruct [:conn, :status, :response, :message, :errors]

  def new(conn, data) when is_map(data) do
    %__MODULE__{
      conn: conn,
      status: data.body["status"],
      response: data.body["response"],
      message: data.body["message"],
      errors: data.body["errors"]
    }
  end

  def ok?(resp), do: resp.status === true

  def params(resp) do
    resp.response[resp.conn.action_desc["output"]["namespace"]]
  end
end
