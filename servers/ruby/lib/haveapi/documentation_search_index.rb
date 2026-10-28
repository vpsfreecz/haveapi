require 'digest'
require 'json'

module HaveAPI
  class DocumentationSearch
    class Index
      attr_reader :payload, :key

      def initialize(description:, base_path:, version:, locale:, visibility:)
        @payload = { format: 1, version: text(version), base_path: text(base_path), locale: text(locale),
                     visibility: text(visibility), resources: [], actions: [], parameters: [] }
        resources(field(description, :resources, {}))
        field(description, :authentication, {}).sort_by { |name, _| name.to_s }.each do |provider, info|
          resources(field(info, :resources, {}), authentication: text(provider))
        end
        freeze_data(@payload)
        @key = Digest::SHA256.hexdigest(JSON.generate(@payload)).freeze
        freeze
      end

      private

      def field(hash, name, default = nil)
        return default unless hash.is_a?(Hash)

        hash.fetch(name) { hash.fetch(name.to_s, default) }
      end

      def text(value)
        value.to_s.dup.freeze
      end

      def strings(values)
        values.compact.map { |value| text(value) }
      end

      def resources(tree, path = [], authentication: nil)
        tree.sort_by { |name, _| name.to_s }.each do |name, resource|
          selected = path + [text(name)]
          label = text(field(resource, :label, name.to_s.humanize))
          index = @payload[:resources].length
          @payload[:resources] << { path: selected, label:, authentication:,
                                    search: strings(selected.flat_map { |part| [part, part.humanize] } +
                                      [selected.join('.'), label, authentication]) }
          field(resource, :actions, {}).sort_by { |action_name, _| action_name.to_s }.each do |action_name, action|
            action(index, selected, action_name, action)
          end
          resources(field(resource, :resources, {}), selected, authentication:)
        end
      end

      def action(resource, path, name, description)
        name = text(name)
        index = @payload[:actions].length
        @payload[:actions] << {
          resource:, name:, label: text(field(description, :label, name.humanize)),
          identifiers: strings([name, "#{path.join('.')}.#{name}", *Array(field(description, :aliases)), field(description, :path)]),
          search: strings([name.humanize, field(description, :method), field(description, :label)])
        }
        %i[input output].each do |direction|
          field(field(description, direction), :parameters, {}).sort_by { |parameter_name, _| parameter_name.to_s }.each do |parameter_name, parameter|
            @payload[:parameters] << { action: index, name: text(parameter_name),
                                       label: text(field(parameter, :label, parameter_name.to_s.humanize)),
                                       type: text(field(parameter, :type)), direction: text(direction),
                                       humanized_name: text(parameter_name.to_s.humanize) }
          end
        end
      end

      def freeze_data(value)
        case value
        when Hash then value.each_value { |entry| freeze_data(entry) }
        when Array then value.each { |entry| freeze_data(entry) }
        end
        value.freeze
      end
    end
  end
end
