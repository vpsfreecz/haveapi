defmodule HaveAPI.Context do
  defstruct [
    :api,
    :prefix,
    :version,
    :resource_path,
    :resource,
    :action,
    :conn,
    :user,
  ]
end
