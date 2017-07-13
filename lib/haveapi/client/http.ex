defmodule HaveAPI.Client.Http do
  def options(url, opts) do
    HTTPoison.options(url, opts[:headers] || [], params: opts[:params] || [])
  end

  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    HTTPoison.request(
      method |> String.downcase |> String.to_atom,
      url,
      body,
      headers,
      options
    )
  end
end
