class VpsAdmin::API::Response
  attr_reader :action

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
    case @action.layout.to_sym
      when :object, :list
        @response[:response][@action.namespace(:output).to_sym]
      else
        @response[:response]
    end
  end

  def message
    @response[:message]
  end

  def errors
    @response[:errors]
  end
end
