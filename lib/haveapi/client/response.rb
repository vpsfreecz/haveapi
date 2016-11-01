# Represents a response from the API.
class HaveAPI::Client::Response
  attr_reader :action

  # Create instance.
  # +action+ being the called action and +response+ a received hash.
  def initialize(action, response)
    @action = action
    @response = response
  end

  def ok?
    @response[:status]
  end

  def failed?
    !ok?
  end

  def response
    case @action.output_layout
      when :object, :object_list, :hash, :hash_list
        @response[:response][@action.namespace(:output).to_sym]
      else
        @response[:response]
    end
  end

  def meta
    @response[:response][:_meta] # FIXME: read _meta from API description
  end

  def to_hash
    response
  end

  def message
    @response[:message]
  end

  def errors
    @response[:errors]
  end

  # Access namespaced params directly.
  def [](key)
    return unless %i(object hash).include?(@action.layout.to_sym)

    @response[:response][@action.namespace(:output).to_sym][key]
  end

  # Iterate over namespaced items directly. Works for only for
  # object_list or hash_list.
  def each
    return unless %i(list).include?(@action.layout.to_sym)

    @response[:response][@action.namespace(:output).to_sym].each
  end

  # Block until the action is completed or timeout occurs. If the block is given,
  # it is regularly called with the action's state.
  #
  # @see HaveAPI::Client::Action#wait_for_completion
  def wait_for_completion(*args, &block)
    id = meta[:action_state_id]
    return nil unless id

    action.wait_for_completion(id, *args, &block)
  end
end
