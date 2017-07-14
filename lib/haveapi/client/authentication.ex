defmodule HaveAPI.Client.Authentication do
  alias HaveAPI.Client

  @callback setup(conn :: map, opts :: list) :: any
  @callback authenticate(request :: map, opts :: any) :: map

  @enforce_keys [:module, :opts]
  defstruct [:module, :opts]

  def new(module, opts) do
    %__MODULE__{module: module, opts: opts}
  end

  def setup(conn, module, opts) do
    auth_opts = apply(module, :setup, [conn, opts])

    %{conn | auth: new(module, auth_opts)}
  end

  def authenticate(%Client.Request{conn: %Client.Conn{auth: nil}} = req), do: req

  def authenticate(req) do
    apply(req.conn.auth.module, :authenticate, [req, req.conn.auth.opts])
  end
end
