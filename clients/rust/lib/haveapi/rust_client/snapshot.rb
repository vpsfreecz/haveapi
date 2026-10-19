require 'json'
require 'digest'
require 'uri'

module HaveAPI::RustClient
  module Snapshot
    KEYS = %w[schema_format api_version protocol_version source_url profile mount_path description].freeze
    PROSE = %w[description label examples message comment title].freeze

    def self.canonical(value)
      normalized = case value
                   when Hash
                     value.keys.map(&:to_s).sort.to_h do |key|
                       [key, canonical_value(value.fetch(key))]
                     end
                   else
                     canonical_value(value)
                   end
      "#{JSON.pretty_generate(normalized)}\n"
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
    rescue JSON::ParserError
      raise Error, 'snapshot is not valid JSON'
    end

    def self.fetch(url:, api_version:, profile:, diagnostics: [])
      require 'haveapi/client'
      version!(api_version)
      endpoint = endpoint!(url)
      suffix = "/v#{api_version}/"
      raise Error, 'fetch URL must select the exact requested version' unless endpoint.path.end_with?(suffix)

      mount = endpoint.path.delete_suffix("v#{api_version}/")
      # The shared metadata client owns parsing/protocol compatibility. Keep the
      # explicit version request at the supplied mount and disable redirects.
      root = endpoint.dup
      root.path = mount
      communicator = HaveAPI::Client::Communicator.new(root.to_s)
      communicator.instance_variable_set(
        :@rest,
        RestClient::Resource.new(root.to_s, max_redirects: 0, open_timeout: 10, read_timeout: 30)
      )
      description = communicator.describe_api(api_version)
      from_description(
        description: JSON.parse(JSON.generate(description)),
        api_version:, protocol_version: communicator.instance_variable_get(:@proto_version),
        source_url: url, profile:, mount_path: mount, diagnostics:
      )
    rescue HaveAPI::Client::ProtocolError
      raise Error, 'incompatible HaveAPI protocol version'
    rescue RestClient::Exception, URI::InvalidURIError
      raise Error, 'metadata acquisition failed (HTTP, redirect or URL error)'
    end

    def self.from_envelope(envelope, api_version:, source_url:, profile:, mount_path: '/', diagnostics: [])
      raise Error, 'metadata envelope is not successful' unless envelope['status'] == true

      from_description(
        description: envelope.fetch('response'), protocol_version: envelope.fetch('version'),
        api_version:, source_url:, profile:, mount_path:, diagnostics:
      )
    rescue KeyError
      raise Error, 'metadata envelope is incomplete'
    end

    def self.from_description(description:, api_version:, protocol_version:, source_url:, profile:, mount_path: '/', diagnostics: [])
      snapshot = {
        'schema_format' => 1, 'api_version' => api_version, 'protocol_version' => protocol_version,
        'source_url' => source_url, 'profile' => profile, 'mount_path' => mount_path,
        'description' => sanitize(description, diagnostics:)
      }
      validate(snapshot)
    end

    # Prose is removed only from structural description objects. Parameter names,
    # validator choice keys and Custom/default JSON are data, never filter keys.
    def self.sanitize(value, context = :description, diagnostics: [], path: [])
      return value.map { |item| sanitize(item, context, diagnostics:, path:) } if value.is_a?(Array)
      return value unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, item), result|
        next if PROSE.include?(key) && !%i[map data choices].include?(context)

        if context == :description && key == 'default' && value['protected'] == true && !item.nil?
          diagnostics << "removed protected default: #{path.join('/')}"
          next
        end

        validate_machine_endpoint(key, item) if context == :description
        child_context = sanitization_context(context, key, item)
        result[key] = if context == :validators && key == 'custom'
                        true
                      elsif context == :choices
                        nil
                      else
                        sanitize(item, child_context, diagnostics:, path: path + [key])
                      end
      end
    end

    def self.validate_machine_endpoint(key, value)
      return if value.nil?
      return endpoint!(value) if key.end_with?('_url')
      return unless %w[path help].include?(key) || key.end_with?('_path')

      path, query = value.is_a?(String) ? value.split('?', 2) : [nil, nil]
      unless path && path.start_with?('/') && !path.include?('#') && safe_segments?(path) &&
             (query.nil? || (key == 'help' && query.match?(/\Amethod=(?:GET|POST|PUT|PATCH|DELETE|OPTIONS)\z/)))
        raise Error, 'unsafe machine endpoint in API description'
      end
    end

    def self.sanitization_context(context, key, item)
      return :data if %i[data choices].include?(context)
      return :description if context == :map
      return :map if %w[resources actions parameters authentication].include?(key)
      return :data if %w[default format].include?(key) && context != :validator
      return item.is_a?(Hash) ? :choices : :data if key == 'values'
      return :validators if key == 'validators'
      return :validator if context == :validators

      :description
    end

    def self.validate(snapshot)
      raise Error, 'snapshot must be an object' unless snapshot.is_a?(Hash)
      raise Error, 'unsupported snapshot envelope keys' unless snapshot.keys.sort == KEYS.sort
      raise Error, 'unsupported snapshot format' unless snapshot['schema_format'] == 1

      version!(snapshot['api_version'])
      protocol = snapshot['protocol_version']
      raise Error, 'unsupported HaveAPI protocol major' unless protocol.is_a?(String) && protocol.match?(/\A2\.\d+\z/)
      raise Error, 'profile must be a nonempty label' unless snapshot['profile'].is_a?(String) && !snapshot['profile'].empty?

      endpoint = endpoint!(snapshot['source_url'])
      mount = snapshot['mount_path']
      unless mount.is_a?(String) && mount.start_with?('/') && mount.end_with?('/') && safe_segments?(mount)
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

      description.fetch('authentication').each do |provider, config|
        raise Error, "invalid authentication description for #{provider}" unless config.is_a?(Hash)

        config.each do |key, value|
          endpoint!(value) if key.end_with?('_url') && value
          next unless key.end_with?('_path') && value
          next if value.is_a?(String) && value.start_with?('/') && !value.match?(/[?#]/) && safe_segments?(value)

          raise Error, "unsafe authentication path for #{provider}"
        end
      end
      snapshot
    end

    def self.version!(version)
      return if version.is_a?(String) && version.match?(/\A\d+(?:\.\d+)*\z/)

      raise Error, 'an explicit numeric API version is required'
    end

    def self.endpoint!(url)
      endpoint = URI.parse(url)
      unless %w[http https].include?(endpoint.scheme) && endpoint.host &&
             endpoint.userinfo.nil? && endpoint.query.nil? && endpoint.fragment.nil? && safe_segments?(endpoint.path)
        raise Error, 'endpoint must be an HTTP URL without credentials, query or fragment'
      end

      endpoint
    rescue URI::InvalidURIError, TypeError
      raise Error, 'invalid endpoint URL'
    end

    def self.safe_segments?(path)
      !path.include?('\\') && !path.start_with?('//') && path.split('/').none? do |segment|
        decoded = URI::DEFAULT_PARSER.unescape(segment)
        %w[. ..].include?(decoded) || decoded.match?(%r{[/\\\x00-\x1f\x7f]})
      end
    end
  end
end
