module HaveAPI::Client
  class ProtocolError < StandardError; end

  class ActionFailed < StandardError
    attr_reader :response

    def initialize(response)
      super("#{response.action.name} failed: #{response.message}")

      @response = response
    end
  end

  class ValidationError < ActionFailed
    attr_reader :errors

    def initialize(action, errors)
      super("#{action.name} failed: input parameters not valid")

      @action = action
      @errors = errors
    end
  end
end
