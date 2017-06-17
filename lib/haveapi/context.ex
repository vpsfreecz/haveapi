defmodule HaveAPI.Context do
  defstruct [
    :prefix,
    :version,
    :resource_path,
    :resource,
    :action,
    :conn,
    :user,
  ]
end
