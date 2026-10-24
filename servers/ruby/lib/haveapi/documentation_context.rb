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
        @version = normalize(:version, version)
        @host = normalize(:host, host)
        @base_url = normalize(:base_url, base_url)
        @version_url = normalize(:version_url, version_url)
        @description = normalize(:description, description)
        @resource_path = normalize(:resource_path, resource_path)
        @resource = normalize(:resource, resource)
        @action_name = normalize(:action_name, action_name)
        @action = normalize(:action, action)
        @sample = normalize(:sample, sample)
        @profile = normalize(:profile, profile)
        freeze
      end

      def with(**changes)
        unless instance_of?(Context)
          return self.class.new(**FIELDS.to_h { |field| [field, public_send(field)] }, **changes)
        end

        unknown = changes.keys - FIELDS
        unless unknown.empty?
          raise ArgumentError, "unknown keyword#{'s' if unknown.length > 1}: #{unknown.map(&:inspect).join(', ')}"
        end

        # Unchanged fields are already owned snapshots; caller-supplied values
        # must still cross the same ownership boundary as initial construction.
        derived = dup
        changes.each do |field, value|
          derived.instance_variable_set("@#{field}", normalize(field, value))
        end
        derived.freeze
      end

      private

      def normalize(field, value)
        case field
        when :version, :host, :base_url, :version_url
          value.to_s.dup.freeze
        when :resource_path
          copy(value.map(&:to_s))
        when :action_name
          value.nil? ? nil : value.to_s.dup.freeze
        when :profile
          value
        else
          copy(value)
        end
      end

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
