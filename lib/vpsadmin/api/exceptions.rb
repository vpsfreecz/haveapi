module VpsAdmin
  module API
    class ActionFailed < Exception
      def initialize(response)
        @response = response
      end

      def message
        "#{@response.action.name} failed: #{@response.message}"
      end
    end
  end
end