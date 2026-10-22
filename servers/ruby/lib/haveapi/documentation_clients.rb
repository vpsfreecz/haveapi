require 'json'
require 'haveapi/documentation_context'

module HaveAPI
  class ClientExample
    class Profile
      attr_reader :language, :package_name, :package_version, :adapter

      def initialize(language:, package_name:, package_version:, adapter:)
        @language = language
        @package_name = package_name.dup.freeze
        @package_version = package_version.dup.freeze
        @adapter = adapter.freeze
        freeze
      end
    end

    class Profiles
      class Invalid < ArgumentError; end

      KEYS = {
        go: %i[import_path module_version description_path generator_version],
        rust: %i[snapshot_path generator_config_path generator_version]
      }.freeze

      def initialize
        @versions = {}
        @rust_versions = {}
      end

      def register(version, **languages)
        raise Invalid, 'Documentation client profiles are already mounted' if @mounted
        raise Invalid, 'Unknown documentation client language' unless (languages.keys - KEYS.keys).empty?

        selected = @versions[version.to_s] ||= {}
        languages.each do |language, config|
          next if config.nil?
          raise Invalid, 'Duplicate documentation client profile' if selected.has_key?(language)

          selected[language] = load_profile(language, config, version.to_s)
        end
      end

      def mount(versions)
        unknown = @versions.keys - Array(versions).map(&:to_s)
        raise Invalid, 'Documentation client profile selects an unavailable API version' unless unknown.empty?
        unless @rust_versions.all? { |version, saved| version == saved }
          raise Invalid, 'Documentation Rust snapshot API version mismatch'
        end

        @versions.each_value(&:freeze)
        @versions.freeze
        @mounted = true
      end

      def for_version(version)
        @versions.fetch(version.to_s, {}).dup.freeze
      end

      private

      def validate_config(language, config)
        unless config.is_a?(Hash) && config.keys.sort == KEYS.fetch(language).sort &&
               config.values.all? { |value| value.is_a?(String) && !value.strip.empty? }
          raise Invalid, 'Invalid documentation client profile fields'
        end
        return if config.fetch(:generator_version).match?(/\A\d+\.\d+\.\d+(?:[-+][\w.-]+)?\z/)

        raise Invalid, 'Invalid documentation generator version'
      end

      def local_file(path)
        raise Invalid, 'Documentation profiles require absolute local files' unless path.start_with?('/') && File.file?(path)

        path
      end

      def load_profile(language, config, version)
        validate_config(language, config)
        language == :go ? load_go(config) : load_rust(config, version)
      rescue LoadError
        raise Invalid, 'Configured documentation client generator is not installed'
      rescue JSON::ParserError, SystemCallError
        raise Invalid, 'Cannot read configured documentation client data'
      rescue Invalid
        raise
      rescue StandardError
        raise Invalid, 'Configured documentation client schema or configuration is invalid'
      end

      def load_go(config)
        name = config.fetch(:import_path)
        version = config.fetch(:module_version)
        unless name.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9._~/-]*\z}) &&
               name.split('/').none? { |part| part.empty? || %w[. ..].include?(part) } &&
               version.match?(/\Av\d+\.\d+\.\d+(?:[-+][\w.-]+)?\z/)
          raise Invalid, 'Invalid Go documentation client package'
        end

        require 'haveapi/go_client/documentation'
        unless config.fetch(:generator_version) == HaveAPI::GoClient::VERSION
          raise Invalid, 'Documentation Go generator version mismatch'
        end

        description = JSON.parse(File.read(local_file(config.fetch(:description_path))))
        adapter = HaveAPI::GoClient::Documentation.new(description:, import_path: name, module_version: version)
        Profile.new(language: :go, package_name: name, package_version: version, adapter:)
      end

      def load_rust(config, api_version)
        require 'haveapi/rust_client/documentation'
        unless config.fetch(:generator_version) == HaveAPI::RustClient::VERSION
          raise Invalid, 'Documentation Rust generator version mismatch'
        end

        snapshot = JSON.parse(File.read(local_file(config.fetch(:snapshot_path))))
        @rust_versions[api_version] = snapshot.fetch('api_version').to_s
        generator_config = Tomlrb.load_file(local_file(config.fetch(:generator_config_path)))
        name = generator_config.fetch('crate_name')
        version = generator_config.fetch('crate_version')
        adapter = HaveAPI::RustClient::Documentation.new(snapshot:, config: generator_config)
        Profile.new(language: :rust, package_name: name, package_version: version, adapter:)
      end
    end
  end
end
