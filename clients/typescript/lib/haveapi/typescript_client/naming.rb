module HaveAPI::TypeScriptClient
  module Naming
    RESERVED = %w[then constructor prototype __proto__].freeze
    EXPORT_RESERVED = %w[createClient RequestExecutor ClientOptions JsonValue API_VERSION SCHEMA_SHA256 RequestOptions executeAction].freeze

    def self.identifier(name)
      raise Error, 'schema name must be a nonempty string' unless name.is_a?(String) && !name.empty?

      value = name.gsub(/[^a-zA-Z0-9_$]/, '_')
      value = "_#{value}" unless value.match?(/\A[a-zA-Z_$]/)
      value
    end

    def self.export(path)
      path.map do |name|
        parts = name.split(/[^a-zA-Z0-9]+/).reject(&:empty?)
        value = parts.map { |part| part[0].upcase + part[1..] }.join
        value = "_#{value}" unless value.match?(/\A[a-zA-Z_$]/)
        value
      end.join('__')
    end

    class Scope
      def initialize(reserved = RESERVED)
        @names = reserved.to_h { |name| [name, "reserved helper #{name}"] }
      end

      def add(name, path)
        if @names.has_key?(name)
          raise Error, "name collision for #{name}: #{@names.fetch(name)} and #{path}"
        end

        @names[name] = path
        name
      end
    end
  end
end
