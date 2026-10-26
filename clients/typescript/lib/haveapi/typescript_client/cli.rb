require 'optparse'
require_relative '../typescript_client'

module HaveAPI::TypeScriptClient
  class Cli
    def self.run(argv = ARGV, out: $stdout, err: $stderr)
      argv = argv.dup
      command = argv.shift
      if command == 'fetch'
        return HaveAPI::Schema::FetchCommand.run(argv, out:, err:, command_name: 'haveapi-typescript-client')
      end

      argv.unshift(command) if %w[-h --help].include?(command)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: haveapi-typescript-client fetch URL [options] | generate --schema FILE --api-version VERSION --output DIR [--check]'
        opts.on('--schema FILE') { |value| options[:schema] = value }
        opts.on('--api-version VERSION') { |value| options[:version] = value }
        opts.on('--output DIR') { |value| options[:output] = value }
        opts.on('--check', 'Check generated output without writing') { options[:check] = true }
        opts.on('-h', '--help') do
          out.puts(opts)
          return 0
        end
      end
      parser.parse!(argv)
      raise Error, 'expected generate subcommand and no positional arguments' unless command == 'generate' && argv.empty?
      raise Error, 'generate requires --schema and --output' unless options[:schema] && options[:output]

      Snapshot.version!(options[:version])
      schema = Snapshot.load(options[:schema])
      raise Error, 'requested API version differs from snapshot' unless schema.fetch('api_version') == options[:version]

      Generator.new(schema:).generate(output: options[:output], check: options[:check])
      0
    rescue Error, OptionParser::ParseError, SystemCallError => e
      err.puts("haveapi-typescript-client: #{e.message}")
      1
    end
  end
end
