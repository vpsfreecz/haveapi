module HaveAPI::Client
  # A list of ResourceInstance objects.
  class ResourceInstanceList < Array
    def initialize(client, api, resource, action, response)
      @response = response

      response.response.each do |hash|
        self << ResourceInstance.new(client, api, resource, action: action, response: hash)
      end
    end

    # Return the API response that created this object.
    def api_response
      @response
    end

    def meta
      @response.meta
    end
  end
end
