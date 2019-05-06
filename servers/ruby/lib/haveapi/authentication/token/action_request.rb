module HaveAPI::Authentication
  module Token
    class ActionRequest
      # @return [Sinatra::Request]
      attr_reader :request

      # @return [Hash]
      attr_reader :input

      # @return [Object, nil]
      attr_reader :user

      # @return [String, nil]
      attr_reader :token

      def initialize(opts = {})
        opts.each do |k, v|
          instance_variable_set(:"@#{k}", v)
        end
      end
    end
  end
end
