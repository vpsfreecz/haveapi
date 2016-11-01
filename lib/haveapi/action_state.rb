module HaveAPI
  # This class is an interface between APIs and HaveAPI for handling of blocking actions.
  # Blocking actions are not executed immediately, but their execution takes an unspecified
  # amount of time. This interface allows to list actions that are pending completion and view
  # their status.
  class ActionState
    # Return an array of objects representing actions that are pending completion.
    # @param [Object] user
    # @param [Integer] offset
    # @param [Integer] limit
    # @return [Array<ActionState>]
    def self.list_pending(user, offset, limit)
      raise NotImplementedError
    end

    # The constructor either gets parameter `id` or `state`. If `state` is not provided,
    # the method should find it using the `id`.
    #
    # When the client is asking about the state of a specific action, lookup using `id`
    # is used. When the client is listing pending actions, instances of this class are
    # created in self.list_pending and are passed the `state` parameter to avoid double
    # lookups. `id` should lead to the same object that would be passed as `state`.
    #
    # @param [Object] user
    # @param [Integer] id action state id
    # @param [Object] state
    def initialize(user, id: nil, state: nil)
      raise NotImplementedError
    end

    # @return [Boolean] true if the action exists
    def valid?
      raise NotImplementedError
    end

    # @return [Boolean] true of the action is finished
    def finished?
      raise NotImplementedError
    end

    # @return [Boolean] true if the action was/is going to be successful
    def status
      raise NotImplementedError
    end

    # @return [Integer] action state id
    def id
      raise NotImplementedError
    end

    # @return [String] human-readable label of this action state
    def label
      raise NotImplementedError
    end

    # @return [Hash]
    def progress
      raise NotImplementedError
    end

    # @return [Boolean] true if the action can be cancelled
    def can_cancel?
      false
    end

    # Stop action execution
    # @raise [RuntimeError] if the cancellation failed
    # @raise [NotImplementedError] if the cancellation is not supported
    # @return [Integer] if the cancellation succeded and is a blocking action
    # @return [truthy] if the cancellation succeeded
    # @return [falsy] if the cancellation failed
    def cancel
      raise NotImplementedError, 'action cancellation is not implemented by this API'
    end
  end
end
