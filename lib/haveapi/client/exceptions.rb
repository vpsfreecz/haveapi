module HaveAPI::Client
  class ActionFailed < Exception
    def initialize(response)
      @response = response
    end

    def message
      "#{@response.action.name} failed: #{@response.message}"
    end
  end

  class ValidationError < ActionFailed
    attr_reader :errors

    def initialize(action, errors)
      @action = action
      @errors = errors
    end

    def message
      "#{@action.name} failed: input parameters not valid"
    end
  end
end
