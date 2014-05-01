require 'optparse'
require 'pp'

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
          format_output(action, action.execute(raw: @opts[:raw]))

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

        case action.layout.to_sym
          when :list
            # Print header row
            response.first.each do |param, _|
              print sprintf('%-25.25s', header_for(action, param))
            end

            puts ''

            # Print items
            response.each do |item|
              item.each do |_, v|
                print sprintf('%-25.25s', v)
              end

              puts ''
            end


          when :object
            response.each do |k, v|
              puts "#{k}: #{v}"
            end


          when :custom
            pp response

        end

        # if s.is_a?(Array) # assume list of items
        #   # find headers
        #   first = response.first
        #
        #   if first.is_a?(Hash)
        #     first.each do |param, _|
        #       print sprintf('%-25.25s', header_for(action, param))
        #     end
        #
        #     puts ''
        #
        #     response.each do |item|
        #       item.each do |_, v|
        #         print sprintf('%-25.25s', v)
        #       end
        #
        #       puts ''
        #     end
        #
        #   else
        #     pp response
        #   end
        #
        # elsif s.is_a?(Hash) # assume item representation
        #   response.each do |k, v|
        #     puts "#{k}: #{v}"
        #   end
        #
        # else
        #   pp response
        # end
      end

      def header_for(action, param)
        params = action.params

        if params.has_key?(param) && params[param][:label]
          params[param][:label]
        else
          param.to_s.upcase
        end
      end
    end
  end
end
