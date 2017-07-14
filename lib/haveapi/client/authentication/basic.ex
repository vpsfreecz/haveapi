defmodule HaveAPI.Client.Authentication.Basic do
  alias HaveAPI.Client

  @behaviour Client.Authentication

  def setup(_conn, opts) do
    %{username: opts[:username], password: opts[:password]}
  end

  def authenticate(req, opts) do
    Client.Request.add_header(
      req,
      "Authorization",
      "basic " <> Base.encode64("#{opts.username}:#{opts.password}")
    )
  end
end
