require 'optparse'
require 'tempfile'

module HaveAPI::Schema
  module FetchCommand
    def self.run(argv, command_name:, out: $stdout, err: $stderr)
      options = {}
      args = argv.dup
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{command_name} fetch URL --api-version VERSION --profile LABEL --output FILE"
        opts.on('--api-version VERSION') { |v| options[:api_version] = v }
        opts.on('--profile LABEL') { |v| options[:profile] = v }
        opts.on('--output FILE') { |v| options[:output] = v }
        opts.on('--basic-user USER') { |v| options[:basic_user] = v }
        opts.on('--basic-password-env ENV_NAME') { |v| options[:password_env] = v }
        opts.on('--token-env ENV_NAME') { |v| options[:token_env] = v }
        opts.on('-h', '--help') do
          out.puts(opts)
          return 0
        end
      end
      parser.parse!(args)
      raise Error, 'fetch requires one URL, --api-version, --profile and --output' unless args.length == 1 && options[:output]
      if options[:token_env] && (options[:basic_user] || options[:password_env])
        raise Error, 'Basic and token authentication are mutually exclusive'
      end
      if options[:basic_user].nil? != options[:password_env].nil?
        raise Error, 'Basic authentication requires --basic-user and --basic-password-env'
      end

      request = { url: args.first, api_version: options[:api_version], profile: options[:profile],
                  basic_user: options[:basic_user], basic_password: secret(options[:password_env]), token: secret(options[:token_env]) }
      Capture.validate_options(**request)
      output = File.expand_path(options[:output])
      validate_output(output)
      diagnostics = []
      value = Capture.fetch(**request, diagnostics: diagnostics)
      bytes = Snapshot.canonical(Snapshot.validate(value))
      validate_output(output)
      Tempfile.create(['.haveapi-schema-', '.json'], File.dirname(output)) do |temp|
        temp.binmode
        temp.write(bytes)
        temp.close
        File.rename(temp.path, output)
      end
      diagnostics.each { |message| err.puts(message) }
      0
    rescue OptionParser::ParseError
      err.puts("#{command_name}: invalid fetch arguments; use --help")
      1
    rescue Error => e
      err.puts("#{command_name}: #{e.message}")
      1
    rescue SystemCallError, IOError, ArgumentError, TypeError
      err.puts("#{command_name}: unable to read or save the snapshot")
      1
    end

    def self.secret(name)
      return nil if name.nil?
      unless name.is_a?(String) && name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        raise Error, 'credential environment variable name is invalid'
      end

      value = ENV.fetch(name, nil)
      raise Error, 'credential environment variable is missing or empty' unless value && !value.empty?

      value
    end

    def self.validate_output(path)
      raise Error, 'snapshot output cannot be a symlink' if File.symlink?(path)
      raise Error, 'snapshot output parent must already exist' unless File.directory?(File.dirname(path))
      raise Error, 'snapshot output must be a regular file' if File.exist?(path) && !File.file?(path)
    end
    private_class_method :secret, :validate_output
  end
end
