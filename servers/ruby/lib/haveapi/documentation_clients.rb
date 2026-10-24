require 'json'
require 'haveapi/documentation_context'
require 'haveapi/documentation_schema'

module HaveAPI
  class ClientExample
    class Profile
      attr_reader :language, :package_name, :package_version, :adapter

      def initialize(language:, package_name:, package_version:, adapter:)
        @language = language
        @package_name = package_name.dup.freeze
        @package_version = package_version&.dup&.freeze
        @adapter = adapter.freeze
        freeze
      end
    end

    class Profiles
      class Invalid < ArgumentError; end

      KEYS = {
        go: %i[import_path module_version description_path generator_version],
        rust: %i[crate_name crate_version source snapshot_path generator_config_path generator_version]
      }.freeze

      def initialize
        @registrations = {}
        @profiles = {}.freeze
      end

      def register(version, **languages)
        raise Invalid, 'Documentation client profiles are already mounted' if @closed
        raise Invalid, 'Unknown documentation client language' unless (languages.keys - KEYS.keys).empty?

        selected = @registrations.fetch(version.to_s, {})
        additions = {}
        languages.each do |language, config|
          next if config.nil?
          raise Invalid, 'Duplicate documentation client profile' if selected.has_key?(language)

          additions[language] = load_profile(language, config)
        end
        @registrations[version.to_s] = selected.merge(additions)
      end

      def mount(versions)
        raise Invalid, 'Documentation client profiles are already mounted' if @closed

        @closed = true
        unknown = @registrations.keys - Array(versions).map(&:to_s)
        raise Invalid, 'Documentation client profile selects an unavailable API version' unless unknown.empty?

        @registrations.each do |version, languages|
          snapshot = languages.dig(:rust, :snapshot)
          if snapshot && snapshot.fetch('api_version').to_s != version
            raise Invalid, 'Documentation Rust snapshot API version mismatch'
          end
        end
      end

      # Publish only after every adapter succeeds, using the complete mounted DSL.
      def finalize(server)
        raise Invalid, 'Documentation client profiles are not ready to finalize' unless @closed && !@finalized

        completed = @registrations.to_h do |version, languages|
          description = if languages.any? { |_language, config| !config[:profile] }
                          safely do
                            context = HaveAPI::Context.new(
                              server, version: server.versions.find { |v| v.to_s == version }, user: nil, endpoint: false, doc: true
                            )
                            StructuralSchema.copy(server.describe_version(context))
                          end
                        end
          profiles = languages.to_h do |language, config|
            profile = config[:profile] || safely { build_profile(language, config, description, server, version) }
            [language, profile]
          end
          [version, profiles.freeze]
        end
        @profiles = completed.freeze
        @registrations = nil
        @finalized = true
      rescue StandardError
        abort_mount
        raise
      end

      def abort_mount
        @profiles = {}.freeze
        @registrations = nil
        @closed = true
        @finalized = true
      end

      def for_version(version)
        @profiles.fetch(version.to_s, {}).dup.freeze
      end

      private

      def validate_config(language, config)
        unless config.is_a?(Hash) && (config.keys - KEYS.fetch(language)).empty? &&
               config.all? { |key, value| %i[source module_version crate_version].include?(key) || nonempty_string?(value) }
          raise Invalid, 'Invalid documentation client profile fields'
        end

        config = config.dup
        config[:generator_version] = config.fetch(:generator_version, HaveAPI::VERSION)
        return config if config[:generator_version].match?(/\A\d+\.\d+\.\d+(?:[-+][\w.-]+)?\z/)

        raise Invalid, 'Invalid documentation generator version'
      end

      def nonempty_string?(value)
        value.is_a?(String) && !value.strip.empty?
      end

      def local_file(path)
        raise Invalid, 'Documentation profiles require absolute local files' unless path.start_with?('/') && File.file?(path)

        path
      end

      def load_profile(language, config)
        safely do
          config = validate_config(language, config)
          language == :go ? load_go(config) : load_rust(config)
        end
      end

      def safely
        yield
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
        name = config[:import_path]
        version = config[:module_version]
        unless nonempty_string?(name) && name.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9._~/-]*\z}) &&
               name.split('/').none? { |part| part.empty? || %w[. ..].include?(part) } &&
               (version.nil? || (version.is_a?(String) && version.match?(/\Av\d+\.\d+\.\d+(?:[-+][\w.-]+)?\z/)))
          raise Invalid, 'Invalid Go documentation client package'
        end

        require 'haveapi/go_client/documentation'
        unless config.fetch(:generator_version) == HaveAPI::GoClient::VERSION
          raise Invalid, 'Documentation Go generator version mismatch'
        end

        prepared = { name: name.dup.freeze, version: version&.dup&.freeze }.freeze
        return prepared unless config.has_key?(:description_path)

        description = JSON.parse(File.read(local_file(config[:description_path])))
        { profile: go_profile(prepared, description) }.freeze
      end

      def go_profile(config, description)
        adapter = HaveAPI::GoClient::Documentation.new(description:, import_path: config[:name], module_version: config[:version])
        profile(:go, config, adapter)
      end

      def load_rust(config)
        require 'haveapi/rust_client/documentation'
        unless config.fetch(:generator_version) == HaveAPI::RustClient::VERSION
          raise Invalid, 'Documentation Rust generator version mismatch'
        end

        legacy = config.has_key?(:generator_config_path)
        if legacy && (config.has_key?(:crate_name) || config.has_key?(:crate_version))
          raise Invalid, 'Conflicting Rust documentation client identities'
        end

        documentation = HaveAPI::RustClient::Documentation
        snapshot = JSON.parse(File.read(local_file(config[:snapshot_path]))) if config.has_key?(:snapshot_path)
        if (!legacy || !snapshot) && !(documentation.respond_to?(:from_description) && documentation.respond_to?(:from_snapshot))
          raise Invalid, 'Documentation Rust generator does not support automatic or inline profiles'
        end

        source = if config.has_key?(:source)
                   raise Invalid, 'Documentation Rust generator does not support source metadata' unless documentation.respond_to?(:validate_source)

                   documentation.validate_source(config[:source])
                 end
        generator_config = Tomlrb.load_file(local_file(config[:generator_config_path])) if legacy
        if legacy
          HaveAPI::RustClient::Generator.validate_config(generator_config) unless snapshot
          name = generator_config.fetch('crate_name')
          version = generator_config.fetch('crate_version')
        else
          name = config[:crate_name]
          version = config[:crate_version]
          HaveAPI::RustClient::Model.validate_package(crate_name: name, crate_version: version)
        end
        prepared = { name: name.dup.freeze, version: version&.dup&.freeze,
                     snapshot:, generator_config:, source: }.freeze
        return prepared unless snapshot

        prepared.merge(profile: rust_profile(prepared, snapshot:)).freeze
      end

      def build_profile(language, config, description, server, version)
        return go_profile(config, description) if language == :go

        arguments = { description:, api_version: version, protocol_version: HaveAPI::PROTOCOL_VERSION,
                      mount_path: server.root }
        if config[:generator_config]
          snapshot = HaveAPI::RustClient::Snapshot.from_description(
            **arguments, source_url: "https://haveapi.invalid#{server.root}v#{version}/", profile: 'server-documentation'
          )
          return rust_profile(config, snapshot:)
        end

        adapter = HaveAPI::RustClient::Documentation.from_description(
          **arguments, crate_name: config[:name], crate_version: config[:version], source: config[:source]
        )
        profile(:rust, config, adapter)
      end

      def rust_profile(config, snapshot:)
        adapter = if config[:generator_config]
                    arguments = { snapshot:, config: config[:generator_config] }
                    arguments[:source] = config[:source] if config[:source]
                    HaveAPI::RustClient::Documentation.new(**arguments)
                  else
                    HaveAPI::RustClient::Documentation.from_snapshot(
                      snapshot:, crate_name: config[:name], crate_version: config[:version], source: config[:source]
                    )
                  end
        profile(:rust, config, adapter)
      end

      def profile(language, config, adapter)
        unless adapter.respond_to?(:resolve) && adapter.respond_to?(:render)
          raise Invalid, 'Documentation client generator has an incompatible adapter interface'
        end

        Profile.new(language:, package_name: config[:name], package_version: config[:version], adapter:)
      end
    end
  end
end
