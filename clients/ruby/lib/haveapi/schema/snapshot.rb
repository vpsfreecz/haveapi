require 'json'
require 'digest'
require 'uri'

module HaveAPI::Schema
  module Snapshot
    KEYS = %w[schema_format api_version protocol_version source_url profile mount_path description].freeze
    PROSE = %w[description label examples message comment title].freeze

    def self.canonical(value)
      "#{JSON.pretty_generate(canonical_value(value))}\n"
    end

    def self.canonical_value(value)
      case value
      when Hash
        value.keys.sort.to_h { |key| [key, canonical_value(value.fetch(key))] }
      when Array
        value.map { |item| canonical_value(item) }
      else
        value
      end
    end

    def self.sha256(snapshot)
      Digest::SHA256.hexdigest(canonical(snapshot))
    end

    def self.load(path)
      validate(JSON.parse(File.read(path)))
    rescue JSON::ParserError, EncodingError
      raise Error, 'snapshot is not valid UTF-8 JSON', cause: nil
    end

    def self.from_envelope(envelope, api_version:, source_url:, profile:, mount_path: '/', diagnostics: [])
      unless envelope.is_a?(Hash) && envelope['status'] == true
        raise Error, 'metadata envelope is not successful'
      end

      from_description(
        description: envelope.fetch('response'), protocol_version: envelope.fetch('version'),
        api_version: api_version, source_url: source_url, profile: profile,
        mount_path: mount_path, diagnostics: diagnostics
      )
    rescue KeyError
      raise Error, 'metadata envelope is incomplete'
    end

    def self.from_description(description:, api_version:, protocol_version:, source_url:, profile:, mount_path: '/', diagnostics: [])
      validate({
        'schema_format' => 1, 'api_version' => api_version, 'protocol_version' => protocol_version,
        'source_url' => source_url, 'profile' => profile, 'mount_path' => mount_path,
        'description' => sanitize(description, diagnostics: diagnostics)
      })
    end

    # Only structural prose is removed. Custom/default JSON and field names are data.
    def self.sanitize(value, context = :description, diagnostics: [], path: [])
      return value.map { |item| sanitize(item, context, diagnostics: diagnostics, path: path) } if value.is_a?(Array)
      return value unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, item), result|
        next if PROSE.include?(key) && !%i[map data choices].include?(context)

        machine_endpoint!(key, item, path + [key]) if context == :description

        if context == :description && key == 'default' && value['protected'] == true && !item.nil?
          diagnostics << "removed protected default: #{path.join('/')}"
          next
        end

        child = child_context(context, key, item)
        result[key] = if context == :validators && key == 'custom'
                        true
                      elsif context == :choices
                        nil
                      else
                        sanitize(item, child, diagnostics: diagnostics, path: path + [key])
                      end
      end
    end

    def self.child_context(context, key, item)
      return :data if %i[data choices].include?(context)
      return :description if context == :map
      return :map if %w[resources actions parameters authentication].include?(key)
      return :data if %w[default format].include?(key) && context != :validator
      return item.is_a?(Hash) ? :choices : :data if key == 'values'
      return :validators if key == 'validators'
      return :validator if context == :validators

      :description
    end

    def self.machine_endpoint!(key, value, path)
      return if value.nil?

      if key.end_with?('_url')
        endpoint!(value)
        return
      end
      return unless %w[path help].include?(key) || key.end_with?('_path')

      route, query = value.is_a?(String) ? value.split('?', 2) : [nil, nil]
      unless route && safe_path?(route) &&
             (query.nil? || (key == 'help' && query.match?(/\Amethod=(?:GET|POST|PUT|PATCH|DELETE|OPTIONS)\z/)))
        raise Error, 'unsafe machine endpoint'
      end
    rescue Error
      raise Error, "unsafe machine endpoint at #{path.join('/')}"
    end

    def self.validate_machine_endpoints(value, context = :description, path = [])
      if value.is_a?(Array)
        value.each { |item| validate_machine_endpoints(item, context, path) }
      elsif value.is_a?(Hash)
        value.each do |key, item|
          machine_endpoint!(key, item, path + [key]) if context == :description
          validate_machine_endpoints(item, child_context(context, key, item), path + [key])
        end
      end
    end

    def self.validate(snapshot)
      raise Error, 'snapshot must be an object' unless snapshot.is_a?(Hash)
      raise Error, 'unsupported snapshot envelope keys' unless snapshot.keys.sort == KEYS.sort
      raise Error, 'unsupported snapshot format' unless snapshot['schema_format'] == 1

      version!(snapshot['api_version'])
      unless snapshot['protocol_version'].is_a?(String) && snapshot['protocol_version'].match?(/\A2\.\d+\z/)
        raise Error, 'unsupported HaveAPI protocol major'
      end
      unless snapshot['profile'].is_a?(String) && !snapshot['profile'].strip.empty?
        raise Error, 'profile must be a nonempty label'
      end

      endpoint = endpoint!(snapshot['source_url'])
      mount = snapshot['mount_path']
      unless mount.is_a?(String) && mount.start_with?('/') && mount.end_with?('/') && safe_path?(mount)
        raise Error, 'invalid capture mount path'
      end

      expected = "#{mount}v#{snapshot['api_version']}/"
      raise Error, 'snapshot source URL/version mismatch' unless endpoint.path == expected

      description = snapshot['description']
      unless description.is_a?(Hash) && description['resources'].is_a?(Hash) &&
             description['authentication'].is_a?(Hash) && description['meta'].is_a?(Hash)
        raise Error, 'invalid API description structure'
      end
      raise Error, 'snapshot description/version mismatch' unless description['help'] == expected

      description['authentication'].each do |provider, auth|
        raise Error, "invalid authentication description at authentication/#{provider}" unless auth.is_a?(Hash)
      end
      validate_machine_endpoints(description)
      snapshot
    end

    def self.version!(version)
      return if version.is_a?(String) && version.match?(/\A\d+(?:\.\d+)*\z/)

      raise Error, 'an explicit numeric API version is required'
    end

    def self.endpoint!(url)
      raise Error, 'invalid endpoint URL' unless url.is_a?(String)

      endpoint = URI.parse(url)
      unless %w[http https].include?(endpoint.scheme) && endpoint.host && endpoint.userinfo.nil? &&
             endpoint.query.nil? && endpoint.fragment.nil? && safe_path?(endpoint.path)
        raise Error, 'endpoint must be an HTTP URL without credentials, query or fragment'
      end

      endpoint
    rescue URI::InvalidURIError, TypeError
      raise Error, 'invalid endpoint URL', cause: nil
    end

    # Compatibility names used by existing generator facades.
    def self.sanitization_context(context, key, item)
      child_context(context, key, item)
    end

    def self.validate_machine_endpoint(key, value)
      machine_endpoint!(key, value, [key])
    end

    def self.safe_segments?(path)
      return false unless path.is_a?(String)

      safe_path?(path.start_with?('/') ? path : "/#{path}")
    end

    def self.safe_path?(path)
      path.is_a?(String) && path.start_with?('/') && !path.start_with?('//') && !path.match?(/[\\?#\x00-\x20\x7f]/) &&
        path.split('/').none? do |segment|
          decoded = URI::DEFAULT_PARSER.unescape(segment)
          %w[. ..].include?(decoded) || decoded.match?(%r{[/\\\x00-\x20\x7f]}) || segment.match?(/%(?![0-9a-fA-F]{2})/)
        end
    end
  end
end
