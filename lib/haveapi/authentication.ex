defmodule HaveAPI.Authentication do
  @callback required_headers() :: [String.t]

  def user(conn), do: conn.private.haveapi_user
end
