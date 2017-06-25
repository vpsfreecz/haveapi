defmodule HaveAPI.Authentication do
  def user(conn), do: conn.private.haveapi_user
end
