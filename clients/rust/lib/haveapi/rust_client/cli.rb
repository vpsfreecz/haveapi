require 'optparse'
require 'tomlrb'
require 'haveapi/rust_client'

module HaveAPI::RustClient
  class Cli
    def self.run(argv = ARGV, out: $stdout, err: $stderr)
      command = argv.shift
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: haveapi-rust-client fetch URL | generate [options]'
        opts.on('--api-version VERSION') { |value| options[:version] = value }
        opts.on('--profile PROFILE') { |value| options[:profile] = value }
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
      when 'fetch'
        raise Error, 'fetch requires one explicit version URL and --profile' unless argv.length == 1 && options[:profile]
        raise Error, '--check is supported only for generation' if options[:check]

        diagnostics = []
        snapshot = Snapshot.fetch(url: argv.first, api_version: options[:version], profile: options[:profile], diagnostics:)
        diagnostics.each { |message| err.puts(message) }
        File.write(options[:output], Snapshot.canonical(snapshot))
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
