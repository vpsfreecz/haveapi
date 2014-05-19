require 'optparse'
require 'pp'
require 'highline/import'
require 'table_print'

module HaveAPI
  module CLI
    class Cli
      def self.run
        c = new
      end

      def initialize
        args, @opts = options
        @api = HaveAPI::Client::Communicator.new(api_url)

        if @action
          method(@action.first).call( * @action[1..-1] )
          exit
        end

        if @opts[:help] || args.empty?
          puts @global_opt.help
          exit(true)
        end

        resources = args[0].split('.')
        action = translate_action(args[1].to_sym)

        action = @api.get_action(resources, action, args[2..-1])

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

          opts.on('-a', '--api URL', 'API URL') do |url|
            options[:client] = url
          end

          opts.on('--list-versions', 'List all available API versions') do
            @action = [:list_versions]
          end

          opts.on('--list-resources VERSION', 'List all resource in API version') do |v|
            @action = [:list_resources, v.sub(/^v/, '')]
          end

          opts.on('--list-actions VERSION', 'List all resources and actions in API version') do |v|
            @action = [:list_actions, v.sub(/^v/, '')]
          end

          opts.on('-r', '--raw', 'Print raw response as is') do
            options[:raw] = true
          end

          opts.on('-u', '--username USER', 'User name') do |u|
            options[:user] = u
          end

          opts.on('-p', '--password PASSWORD', 'Password') do |p|
            options[:password] = p
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

      def list_resources(v)
        @api.describe_api(v)[:resources].each do |resource, children|
          nested_resource(resource, children, false)
        end
      end

      def list_actions(v)
        @api.describe_api(v)[:resources].each do |resource, children|
          nested_resource(resource, children, true)
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

        s = action.structure
        namespace = action.namespace(:output).to_sym

        case action.layout.to_sym
          when :list
            tp response[namespace]


          when :object
            response[namespace].each do |k, v|
              puts "#{k}: #{v}"
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

      def params_valid?(action)
        if action.auth?
          @opts[:user] ||= ask('User name: ') { |q| q.default = nil }

          @opts[:password] ||= ask('Password: ') do |q|
            q.default = nil
            q.echo = false
          end
        end

        if action.auth? && !(@opts[:user] || @opts[:password])
          return false
        end

        @api.login(@opts[:user], @opts[:password])

        true
      end

      protected
      def default_url
        'http://localhost:4567'
      end
    end
  end
end
