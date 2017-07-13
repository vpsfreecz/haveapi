defmodule HaveAPI.Client.Conn do
  @enforce_keys [:url]
  defstruct [:url, :version, :description, :resource_path, :path_params]
end
