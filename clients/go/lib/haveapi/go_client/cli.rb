require 'optparse'

module HaveAPI
  module GoClient
    class Cli
      def self.run(argv = ARGV, out: $stdout, err: $stderr)
        argv = argv.dup
        if %w[fetch generate].include?(argv.first)
          require_shared_schema
          return HaveAPI::Schema::FetchCommand.run(argv.drop(1), out:, err:, command_name: 'haveapi-go-client') if argv.first == 'fetch'

          generate_saved(argv.drop(1), out:)
        else
          legacy(argv, out:)
        end
        0
      rescue OptionParser::ParseError, SystemCallError, ArgumentError => e
        err.puts("haveapi-go-client: #{e.message}")
        1
      rescue StandardError => e
        raise unless defined?(HaveAPI::Schema::Error) && e.is_a?(HaveAPI::Schema::Error)

        err.puts("haveapi-go-client: #{e.message}")
        1
      end

      def self.require_shared_schema
        require 'haveapi/schema'
        return if defined?(HaveAPI::Schema::Snapshot) && defined?(HaveAPI::Schema::FetchCommand)

        raise ArgumentError, 'loaded haveapi-client does not provide the required shared schema API'
      rescue LoadError
        raise ArgumentError, 'shared haveapi-client schema API is unavailable; prepare the component bundle from this source release'
      end

      def self.generate_saved(argv, out:)
        options = { package: 'client' }
        parser = OptionParser.new do |opts|
          opts.banner = 'Usage: haveapi-go-client generate --schema FILE --api-version VERSION --output DIR [--module MODULE] [--package NAME]'
          opts.on('--schema FILE') { |value| options[:schema] = value }
          opts.on('--api-version VERSION') { |value| options[:version] = value }
          opts.on('--output DIR') { |value| options[:output] = value }
          opts.on('--module MODULE') { |value| options[:module] = value }
          opts.on('--package NAME') { |value| options[:package] = value }
          opts.on('-h', '--help') do
            out.puts(opts)
            return 0
          end
        end
        parser.parse!(argv)
        raise ArgumentError, 'generate requires --schema, --output and no positional arguments' unless argv.empty? && options[:schema] && options[:output]

        HaveAPI::Schema::Snapshot.version!(options[:version])
        snapshot = HaveAPI::Schema::Snapshot.load(options[:schema])
        raise ArgumentError, 'requested API version differs from snapshot' unless snapshot.fetch('api_version') == options[:version]

        require 'haveapi/go_client'
        # The existing generator consumes the symbol-key JSON representation used
        # by the dynamic Ruby communicator, including nested validator/Custom keys.
        description = JSON.parse(JSON.generate(snapshot.fetch('description')), symbolize_names: true)
        generator = Generator.from_description(description, options[:output], options)
        generator.generate
        generator.go_fmt
      end

      def self.legacy(argv, out:)
        options = { package: 'client' }
        parser = OptionParser.new do |opts|
          opts.banner = 'Usage: haveapi-go-client [options] <api url> <destination>'
          opts.on('--version VERSION', 'Use specified API version (otherwise server default)') { |value| options[:version] = value }
          opts.on('--module MODULE') { |value| options[:module] = value }
          opts.on('--package PKG') { |value| options[:package] = value }
          opts.on('--basic-user USER') { |value| options[:basic_user] = value }
          opts.on('--basic-password PASSWORD') { |value| options[:basic_password] = value }
          opts.on('-h', '--help') do
            out.puts(opts)
            return 0
          end
        end
        parser.parse!(argv)
        raise ArgumentError, 'legacy mode requires an API URL and destination' unless argv.length == 2

        require 'haveapi/go_client'
        generator = Generator.new(argv[0], argv[1], options)
        generator.generate
        generator.go_fmt
      end
    end
  end
end
