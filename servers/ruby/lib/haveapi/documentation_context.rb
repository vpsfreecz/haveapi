require 'haveapi/client_example'

module HaveAPI
  class ClientExample
    # A request-local snapshot: never freeze or retain the server's shared help.
    class Context
      FIELDS = %i[version host base_url version_url description resource_path resource action_name action sample profile].freeze
      attr_reader(*FIELDS)

      def initialize(version:, host:, base_url:, version_url:, description:,
                     resource_path: [], resource: nil, action_name: nil, action: nil,
                     sample: nil, profile: nil)
        @version = version.to_s.dup.freeze
        @host = host.to_s.dup.freeze
        @base_url = base_url.to_s.dup.freeze
        @version_url = version_url.to_s.dup.freeze
        @description = copy(description)
        @resource_path = copy(resource_path.map(&:to_s))
        @resource = copy(resource)
        @action_name = action_name.nil? ? nil : action_name.to_s.dup.freeze
        @action = copy(action)
        @sample = copy(sample)
        @profile = profile
        freeze
      end

      def with(**changes)
        self.class.new(**FIELDS.to_h { |field| [field, public_send(field)] }, **changes)
      end

      private

      def copy(value)
        case value
        when Hash
          value.to_h { |key, item| [copy(key), copy(item)] }.freeze
        when Array
          value.map { |item| copy(item) }.freeze
        when String
          value.dup.freeze
        else
          value
        end
      end
    end
  end
end
