module HaveAPI::Client
  # A list of ResourceInstance objects.
  class ResourceInstanceList < Array
    def initialize(client, api, resource, action, response)
      super()
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

    # Return the total count of items.
    # Note that for this method to work, the action that returns this
    # object list must be invoked with +meta: {count: true}+, otherwise
    # the object count is not sent.
    def total_count
      meta[:total_count]
    end
  end
end
