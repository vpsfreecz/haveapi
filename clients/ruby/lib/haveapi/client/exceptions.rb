module HaveAPI::Client
  class ProtocolError < StandardError; end

  class ActionFailed < StandardError
    attr_reader :response

    def initialize(response)
      if response.respond_to?(:action)
        msg = response.action.client_message(
          'errors.action_failed',
          action: response.action.name,
          message: response.message
        )
        super(msg)
      else
        super(response.to_s)
      end

      @response = response
    end
  end

  class ValidationError < ActionFailed
    attr_reader :errors

    def initialize(action, errors)
      message = action.client_message('errors.input_parameters_not_valid')
      super(action.client_message('errors.action_failed', action: action.name, message: message))

      @action = action
      @errors = errors
    end
  end
end
