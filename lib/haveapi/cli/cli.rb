require 'optparse'
require 'pp'
require 'highline/import'
require 'table_print'
require 'yaml'

module HaveAPI
  module CLI
    class Cli
      class << self
        attr_accessor :auth_methods

        def run
          c = new
        end

        def register_auth_method(name, klass)
          @auth_methods ||= {}
          @auth_methods[name] = klass
        end
      end

      def initialize
        @config = read_config || {}
        args, @opts = options

        @api = HaveAPI::Client::Communicator.new(api_url)

        if @action
          method(@action.first).call( * @action[1..-1] )
          exit
        end

        if (@opts[:help] && args.empty?) || args.empty?
          puts @global_opt.help
          puts "\nAvailable resources:"
          list_resources
          exit(true)
        end

        resources = args[0].split('.')

        if args.count == 1
          describe_resource(resources)
          exit(true)
        end

        action = translate_action(args[1].to_sym)

        action = @api.get_action(resources, action, args[2..-1])

        action.update_description(@api.describe_action(action)) if authenticate(action)

        @input_params = parameters(action)

        if action
          unless params_valid?(action)
            warn 'Missing required parameters'
          end

          ret = action.execute(@input_params, raw: @opts[:raw])

          if ret[:status]
            format_output(action, ret[:response])
          else
            warn "Action failed: #{ret[:message]}"

            if ret[:errors].any?
              puts 'Errors:'
              ret[:errors].each do |param, e|
                puts "\t#{param}: #{e.join('; ')}"
              end
            end
          end

        else
          warn "Action #{ARGV[0]}##{ARGV[1]} not valid"
          exit(false)
        end
      end

      def api_url
        @opts[:client]
      end

      def options
        options = {
            client: default_url,
            verbose: false,
        }

        @global_opt = OptionParser.new do |opts|
          opts.banner = "Usage: #{$0} [options] <resource> <action> [objects ids] [-- [parameters]]"

          opts.on('-u', '--api URL', 'API URL') do |url|
            options[:client] = url
          end

          opts.on('-a', '--auth METHOD', Cli.auth_methods.keys, 'Authentication method') do |m|
            options[:auth] = m
            @auth = Cli.auth_methods[m].new(server_config(options[:client])[:auth][m])
            @auth.options(opts)
          end

          opts.on('--list-versions', 'List all available API versions') do
            @action = [:list_versions]
          end

          opts.on('--list-auth-methods [VERSION]', 'List available authentication methods') do |v|
            @action = [:list_auth, v && v.sub(/^v/, '')]
          end

          opts.on('--list-resources [VERSION]', 'List all resource in API version') do |v|
            @action = [:list_resources, v && v.sub(/^v/, '')]
          end

          opts.on('--list-actions [VERSION]', 'List all resources and actions in API version') do |v|
            @action = [:list_actions, v && v.sub(/^v/, '')]
          end

          opts.on('-r', '--raw', 'Print raw response as is') do
            options[:raw] = true
          end

          opts.on('-s', '--save', 'Save credentials to config file for later use') do
            options[:save] = true
          end

          opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
            options[:verbose] = v
          end

          opts.on('-h', '--help', 'Show this message') do
            options[:help] = true
          end
        end

        args = []

        ARGV.each do |arg|
          if arg == '--'
            break
          else
            args << arg
          end
        end

        @global_opt.parse!(args)

        # p options
        #p ARGV

        [args, options]
      end

      def parameters(action)
        options = {}
        sep = ARGV.index('--')

        @action_opt = OptionParser.new do |opts|
          opts.banner = ''

          action.input[:parameters].each do |name, p|
            opts.on(param_option(name, p), p[:description] || p[:label] || '') do |*args|
              options[name] = args.first
            end
          end

          opts.on('-h', '--help', 'Show this message') do
            @opts[:help] = true
          end
        end

        if @opts[:help]
          puts @global_opt.help
          puts ''
          print 'Action parameters:'
          puts @action_opt.help
          exit
        end

        return {} unless sep

        @action_opt.parse!(ARGV[sep+1..-1])

        options
      end

      def param_option(name, p)
        ret = '--'
        name = name.to_s.dasherize

        if p[:type] == 'Boolean'
          ret += "[no-]#{name}"

        else
          ret += "#{name} #{name.underscore.upcase}"
        end

        ret
      end

      def translate_action(action)
        tr = {
            list: :index,
            new: :create,
            change: :update
        }

        if tr.has_key?(action)
          return tr[action]
        end

        action
      end

      def list_versions
        desc = @api.describe_api

        desc[:versions].each do |v, _|
          next if v == :default

          v_int = v.to_s.to_i

          puts "#{v_int == desc[:default_version] ? '*' : ' '} v#{v}"
        end
      end

      def list_auth(v=nil)
        desc = @api.describe_api

        desc[:versions][(v && v.to_sym) || desc[:default_version].to_s.to_sym][:authentication].each_key do |auth|
          puts auth if Cli.auth_methods.has_key?(auth)
        end
      end

      def list_resources(v=nil)
        desc = @api.describe_api

        desc[:versions][(v && v.to_sym) || desc[:default_version].to_s.to_sym][:resources].each do |resource, children|
          nested_resource(resource, children, false)
        end
      end

      def list_actions(v=nil)
        desc = @api.describe_api

        desc[:versions][(v && v.to_sym) || desc[:default_version].to_s.to_sym][:resources].each do |resource, children|
          nested_resource(resource, children, true)
        end
      end

      def describe_resource(path)
        desc = @api.describe_resource(path)

        unless desc
          warn "Resource #{path.join('.')} does not exist"
          exit(false)
        end

        unless desc[:resources].empty?
          puts 'Resources:'

          desc[:resources].each_key do |r|
            puts "  #{r}"
          end
        end

        puts '' if !desc[:resources].empty? && !desc[:actions].empty?

        unless desc[:actions].empty?
          puts 'Actions:'

          desc[:actions].each_key do |a|
            puts "  #{a}"
          end
        end
      end

      def nested_resource(prefix, children, actions=false)
        if actions
          children[:actions].each do |action, _|
            puts "#{prefix}##{action}"
          end
        else
          puts prefix
        end

        children[:resources].each do |resource, children|
          nested_resource("#{prefix}.#{resource}", children, actions)
        end
      end

      def format_output(action, response)
        if @opts[:raw]
          puts response
          return
        end

        return if response.empty?

        namespace = action.namespace(:output).to_sym

        case action.layout.to_sym
          when :list
            cols = []

            action.params.each do |name, p|
              if p[:type] == 'Resource'
                cols << {name => {display_method: ->(r) { r[name][p[:value_label].to_sym] } }}
              else
                cols << name
              end
            end

            tp response[namespace], *cols


          when :object
            response[namespace].each do |k, v|

              if action.params[k][:type] == 'Resource'
                puts "#{k}: #{v[action.params[k][:value_label].to_sym]}"
              else
                puts "#{k}: #{v}"
              end
            end


          when :custom
            pp response[namespace]

        end
      end

      def header_for(action, param)
        params = action.params

        if params.has_key?(param) && params[param][:label]
          params[param][:label]
        else
          param.to_s.upcase
        end
      end

      def authenticate(action)
        if action.auth?
          if @auth
            @auth.communicator = @api
            @auth.validate
            @auth.authenticate

            if @opts[:save]
              server_config(api_url)[:auth][@opts[:auth]] = @auth.save
              write_config
            end

          else
            # FIXME: exit as auth is needed and has not been selected
          end

          return true
        end

        false
      end

      def params_valid?(action)
        true # FIXME
      end

      protected
      def default_url
        'http://localhost:4567'
      end

      def config_path
        "#{Dir.home}/.haveapi-client.yml"
      end

      def write_config
        File.open(config_path, 'w') do |f|
          f.write(YAML.dump(@config))
        end
      end

      def read_config
        @config = YAML.load_file(config_path) if File.exists?(config_path)
      end

      def server_config(url)
        unless @config[:servers]
          @config[:servers] = [{url: url, auth: {}}]
          return @config[:servers].first
        end

        @config[:servers].each do |s|
          return s if s[:url] == url
        end

        @config[:servers] << {url: url, auth: {}}
        @config[:servers].last
      end
    end
  end
end
