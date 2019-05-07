module HaveAPI::Authentication
  module Token
    class ActionResult
      # @param complete [Boolean]
      # @return [Boolean]
      attr_accessor :complete

      # @param error [String]
      # @return [String, nil]
      attr_accessor :error

      # @param token [String]
      # @return [String, nil]
      attr_accessor :token

      # @param valid_to [Time]
      # @return [Time, nil]
      attr_accessor :valid_to

      # @param next_action [String]
      # @return [String, nil]
      attr_accessor :next_action

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

      def complete?
        @complete ? true : false
      end
    end
  end
end
