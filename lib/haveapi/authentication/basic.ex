defmodule HaveAPI.Authentication.Basic do
  @callback find_user(%Plug.Conn{}, String.t, String.t) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      def name, do: :basic

      def describe(_ctx) do
        %{
          description: "Authentication using HTTP basic. Username and password is passed " <>
                       "via HTTP header. Its use is forbidden from web browsers."
        }
      end

      def authenticate(conn) do
        header = Enum.find(
          conn.req_headers,
          fn {k,v} -> k == "authorization" end
        )

        if header do
          {_, auth} = header
          [_, auth] = String.split(auth, ~r{\s}, trim: true)
          [user, password] = auth |> Base.decode64! |> String.split(":")

          find_user(conn, user, password)

        else
          nil
        end

      rescue ArgumentError ->
        nil
      end
    end
  end
end
