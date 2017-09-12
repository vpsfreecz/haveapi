defmodule HaveAPI.Client.Authentication do
  alias HaveAPI.Client

  @callback setup(conn :: map, opts :: list) ::  {:ok, map} | {:error, String.t}
  @callback authenticate(request :: map, opts :: any) :: map
  @callback logout(conn :: map, opts :: any) :: :ok | {:error, String.t}

  @enforce_keys [:module, :opts]
  defstruct [:module, :opts]

  def new(module, opts) do
    %__MODULE__{module: module, opts: opts}
  end

  def setup(conn, module, opts) do
    case apply(module, :setup, [conn, opts]) do
      {:ok, auth_opts} ->
        {:ok, %{conn | auth: new(module, auth_opts)}}

      {:error, msg} ->
        {:error, msg}
    end
  end

  def authenticate(%Client.Request{conn: %Client.Conn{auth: nil}} = req), do: req

  def authenticate(req) do
    apply(req.conn.auth.module, :authenticate, [req, req.conn.auth.opts])
  end

  def logout(%Client.Conn{auth: nil} = conn), do: conn

  def logout(conn) do
    case apply(conn.auth.module, :logout, [conn, conn.auth.opts]) do
      :ok ->
        %{conn | auth: nil}

      {:error, msg} ->
        {:error, msg}
    end
  end
end
