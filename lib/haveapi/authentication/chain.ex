defmodule HaveAPI.Authentication.Chain do
  def authenticate(conn, [chain: chain]) do
    user = Enum.reduce_while(
      chain,
      nil,
      fn auth, acc ->
        case auth.authenticate(conn) do
          :halt ->
            {:halt, acc}

          ^acc ->
            {:cont, acc}

          user ->
            {:halt, user}
        end
      end
    )

    %{conn | private: Map.put(conn.private, :haveapi_user, user)}
  end
end
