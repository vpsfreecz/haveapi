module HaveAPI::Authentication
  module Token
    class ActionResult
      # @param error [String]
      # @return [String, nil]
      attr_accessor :error

      # @param token [String]
      # @return [String, nil]
      attr_accessor :token

      # @param valid_to [Time]
      # @return [Time, nil]
      attr_accessor :valid_to

      def initialize
        @ok = false
      end

      def ok
        @ok = true
        self
      end

      def ok?
        @ok && @error.nil?
      end
    end
  end
end
