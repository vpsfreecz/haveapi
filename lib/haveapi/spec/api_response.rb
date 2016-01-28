module HaveAPI::Spec    
  # This class wraps raw reply from the API and provides a more friendly
  # interface.
  class ApiResponse
    def initialize(body)
      @data = JSON.parse(body, symbolize_names: true)
    end

    def envelope
      @data
    end

    def status
      @data[:status]
    end

    def ok?
      @data[:status]
    end

    def failed?
      !ok?
    end

    def response
      @data[:response]
    end

    def message
      @data[:message]
    end

    def errors
      @data[:errors]
    end

    def [](k)
      @data[:response][k]
    end
  end
end
