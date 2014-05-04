require 'optparse'
require 'pp'
require 'highline/import'

module VpsAdmin
  module CLI
    class Cli
      def self.run
        c = new
      end

      def initialize
        @opts = options
        @api = VpsAdmin::API::Client.new(@opts[:api])

        if @action
          method(@action.first).call( * @action[1..-1] )
          exit
        end

        resources = ARGV[0].split('.')
        action = translate_action(ARGV[1].to_sym)

        action = @api.get_action(resources, action, ARGV[2..-1])

        if action
          unless params_valid?(action)
            warn 'Missing required parameters'
          end

          ret = action.execute(raw: @opts[:raw])

          if ret[:status]
            format_output(action, ret[:response])
          else
            warn "Error occured: #{ret[:message]}"
          end

        else
          warn "Action #{ARGV[0]}##{ARGV[1]} not valid"
          exit(false)
        end
      end

      def options
        options = {
            api: 'http://localhost:4567',
            verbose: false,
        }

        OptionParser.new do |opts|
          opts.banner = 'Usage: vpsadminctl [options] <resource> <action> [parameters]'

          opts.on('-a', '--api URL', 'API URL') do |url|
            options[:api] = url
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
        end.parse!

        #p options
        #p ARGV

        options
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
        namespace = action.namespace.to_sym

        case action.layout.to_sym
          when :list
            # Print header row
            response[namespace].first.each do |param, _|
              print sprintf('%-25.25s', header_for(action, param))
            end

            puts ''

            # Print items
            response[namespace].each do |item|
              item.each do |_, v|
                print sprintf('%-25.25s', v)
              end

              puts ''
            end


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
    end
  end
end
