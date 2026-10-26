require 'optparse'
require 'tomlrb'
require 'haveapi/rust_client'

module HaveAPI::RustClient
  class Cli
    def self.run(argv = ARGV, out: $stdout, err: $stderr)
      argv = argv.dup
      command = argv.shift
      if command == 'fetch'
        return HaveAPI::Schema::FetchCommand.run(argv, out:, err:, command_name: 'haveapi-rust-client')
      end

      argv.unshift(command) if %w[-h --help].include?(command)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: haveapi-rust-client fetch URL | generate [options]'
        opts.on('--api-version VERSION') { |value| options[:version] = value }
        opts.on('--schema FILE') { |value| options[:schema] = value }
        opts.on('--config FILE') { |value| options[:config] = value }
        opts.on('--output PATH') { |value| options[:output] = value }
        opts.on('--check', 'Check without modifying destination') { options[:check] = true }
        opts.on('-h', '--help') do
          out.puts(opts)
          return 0
        end
      end
      parser.parse!(argv)
      Snapshot.version!(options[:version])
      raise Error, '--output is required' unless options[:output]

      case command
      when 'generate'
        unless argv.empty? && options[:schema] && options[:config]
          raise Error, 'generate requires --schema and --config'
        end

        snapshot = Snapshot.load(options[:schema])
        raise Error, 'requested API version differs from snapshot' unless options[:version] == snapshot.fetch('api_version')

        config = Tomlrb.load_file(options[:config])
        Generator.new(schema: snapshot, config:).generate(output: options[:output], check: options[:check])
      else
        raise Error, 'expected fetch or generate subcommand'
      end
      0
    rescue Error, OptionParser::ParseError, Tomlrb::ParseError, SystemCallError => e
      err.puts("haveapi-rust-client: #{e.message}")
      1
    end
  end
end
