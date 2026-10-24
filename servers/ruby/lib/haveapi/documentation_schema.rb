require 'json'

module HaveAPI
  class ClientExample
    # Private naming/type input, never a request's authorized help or samples.
    module StructuralSchema
      BUILTIN_VALIDATORS = %w[present number include exclude format length confirm accept].freeze

      def self.copy(description)
        result = JSON.parse(JSON.generate(description))
        resources(result['resources'])
        result.fetch('authentication', {}).each_value do |provider|
          prose(provider)
          resources(provider['resources'])
        end
        freeze_data(result)
      end

      def self.resources(map)
        return unless map

        map.each_value do |resource|
          prose(resource)
          resource.fetch('actions', {}).each_value do |action|
            prose(action)
            action.delete('examples')
            parameters(action['input'])
            parameters(action['output'])
            action.fetch('meta', nil)&.each_value do |metadata|
              next unless metadata

              parameters(metadata['input'])
              parameters(metadata['output'])
            end
          end
          resources(resource['resources'])
        end
      end

      def self.parameters(group)
        return unless group

        group.fetch('parameters', {}).each_value do |parameter|
          prose(parameter)
          parameter.delete('default')
          parameter.fetch('validators', {}).each do |name, validator|
            prose(validator) if BUILTIN_VALIDATORS.include?(name) && validator.is_a?(Hash)
          end
        end
      end

      def self.prose(object)
        %w[label description message].each { |key| object.delete(key) }
      end

      def self.freeze_data(value)
        case value
        when Hash
          value.each do |key, item|
            freeze_data(key)
            freeze_data(item)
          end
        when Array
          value.each { |item| freeze_data(item) }
        end
        value.freeze
      end

      private_class_method :resources, :parameters, :prose, :freeze_data
    end
    private_constant :StructuralSchema
  end
end
