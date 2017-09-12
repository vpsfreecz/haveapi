defmodule HaveAPI.Action.Show do
  @moduledoc """
  Action template for showing a single resource identified by its id.
  All resources should have this action implemented, in order to be used
  with HaveAPI and its clients, especially if you're using resource
  associations.

  Action `Show` is called either by a client via the API , or in case
  of resource associations by HaveAPI internally. If you declare an association
  between resources, than the associated resource _must_ have action `Show`,
  as it is used to return the data for the association.

  If called externally through the API, the callbacks are called in
  the following order:

  - `find(req)` - should return an internal representation of the resource.
    The return value is then passed to subsequent callbacks as `item`.
  - `check(req, item)` - should double-check if the user from `req`
     is authorized to this resource
  - `return(req, item)` - return a response that is to be processed and sent
    to the client, it's the same return value as from the action `exec/1`
    callback.

  Only `find/1` has to be implemented. `check/2` by default returns `true`,
  because we rely on `authorize/2` to be sufficient. `return/2` by default
  returns the value returned by `find/1` unchanged.

  The same callbacks are also used when resolving an associated resource.
  Consider the following API:

      defmodule Group do
        use HaveAPI.Resource

        defmodule Show do
          use HaveAPI.Action.Show

          output do
            string :group_name
          end

          def authorize(_req, _user), do: :allow
          def find(req), do: do_find_group(req.params[:group_id])
        end

        actions [Show]
      end

      defmodule User do
        use HaveAPI.Resource

        defmodule Show do
          use HaveAPI.Action.Show

          output do
            string :user_name
            resource [Group]
          end

          def authorize(_req, _user), do: :allow
          def find(req), do: do_find_user(req.params[:user_id])
          def return(_req, user) do
            %{user_name: user.name, group: [user.group_id]}
          end
        end

        actions [Show]
      end

  In the example above, we have resource `User`, whose action `Show` returns
  an association on `Group`, i.e. user belongs to group. When `User.Show` is
  called, it sets `group` output parameter to a list of path parameters required
  to call `Group.Show`, i.e. `[user.group_id]`. In this case, HaveAPI calls
  callbacks of `Group.Show` just as if it had been called by a client.

  This solution works, but is not the most effective one. For example, when
  users and groups are stored in a database, we can fetch a list of all users
  and their group using one query. When HaveAPI would be resolving associations,
  `Group.Show.find/1` would call an additional query for every user to get
  his group. To reduce the query count, we can change `User.Show.return/2`
  to return the group representation, just as if `Group.Show.find/1` would
  have returned it:

      def return(_req, user) do
        %{user_name: user.name, group: {[user.group_id], user.group}}
      end

  Notice that `:group` is now a tuple of path parameters and the representation
  itself. When HaveAPI sees this, it does not call `Group.Show.find/1`
  callback, but only `Group.Show.check/2` and `Group.Show.return/2`. This is
  especially useful when returning a list of many users. However, it is the
  developer's responsibility to ensure that `find/1` and the user resource
  return the same object representing groups, or that you cope with the fact
  that they may be different.

  The `check/2` callback may seem to be duplicit to `authorize/2`, but it is
  necessary, because some authorization logic may also happen in `find/1`, which
  does not have to be called when resolving associations. In such cases, the
  developer can implement the `check/2` callback to ensure that the user is
  authorized to access the resource.
  """

  use HaveAPI.Action

  @doc """
  Find internal representation of a resource identified by `req`.

  If `nil` is returned, the resource is considered not to exist.
  """
  @callback find(req :: map) :: nil | any

  @doc """
  Ensure that the user has access to this resource.

  Is used mainly for associations, where `find/1` does not have to be called,
  and if some authorization logic happens there, it won't be effective.

  Returns `true` by default.
  """
  @callback check(req :: map, item :: any) :: boolean

  @doc """
  Transform the internal resource representation `item` into a response to
  the client.

  Returns the same value as `HaveAPI.Action.exec/1`. By default returns `item`
  unchanged.
  """
  @callback return(req :: map, item :: any) :: any

  method :get
  route "/:%{resource}_id"
  aliases [:find]

  meta :global do
    output do
      custom :url_params
      boolean :resolved
    end
  end

  def use_template do
    quote do
      @behaviour unquote(__MODULE__)

      def exec(req) do
        unquote(__MODULE__).exec(__MODULE__, req)
      end

      def check(_req, _item), do: true
      def return(_req, item), do: item

      defoverridable [check: 2, return: 2]
    end
  end

  def exec(mod, req) do
    v = mod.find(req)

    case v do
      nil ->
        {:error, "Object not found", http_status: 404}

      {:error, msg} ->
        {:error, msg}

      {:error, msg, opts} ->
        {:error, msg, opts}

      item ->
        if mod.check(req, item) do
          res = HaveAPI.Action.Output.build(req, mod.return(req, item))

          if res.status do
            add_local_metadata(req, res)

          else
            res
          end

        else
          {:error, "Access denied", http_status: 403}
        end
    end
  end

  def add_local_metadata(req, res) do
    if res.output[:id] do
      %{res | meta: %{
          url_params: (req.params |> Keyword.delete_first(:glob) |> Keyword.values),
          resolved: true
      }}

    else
      res
    end
  end
end
