require 'optparse'
require 'pp'
require 'yaml'
require 'time'
require 'date'
require 'haveapi/cli/utils'

module HaveAPI::CLI
  class Cli
    class << self
      attr_accessor :auth_methods, :commands

      def run
        c = new
      rescue Interrupt
        warn 'Interrupted'
        exit(false)
      end

      def register_auth_method(name, klass)
        @auth_methods ||= {}
        @auth_methods[name] = klass
      end

      def register_command(cmd)
        @commands ||= []
        @commands << cmd
      end
    end

    include Utils

    def initialize
      @config = read_config || {}
      args, @opts = options

      connect_api unless @api

      if @action
        method(@action.first).call(* @action[1..])
        exit
      end

      if (@opts[:help] && args.empty?) || args.empty?
        show_help do
          puts "\nAvailable resources:"
          list_resources
        end
      end

      resources = args[0].split('.')

      if cmd = find_command(resources, args[1])
        authenticate if @auth
        c = cmd.new(@opts, HaveAPI::Client::Client.new(nil, communicator: @api))

        cmd_opt = OptionParser.new do |opts|
          opts.banner = "\nCommand options:"
          c.options(opts)

          opts.on('-h', '--help', 'Show this message') do
            show_help do
              puts cmd_opt.help
            end
          end
        end

        if @opts[:help]
          show_help do
            puts cmd_opt.help
          end
        end

        if sep = ARGV.index('--')
          cmd_opt.parse!(ARGV[sep + 1..])
        end

        c.exec(args[2..] || [])

        exit
      end

      if args.count == 1
        describe_resource(resources)
        exit
      end

      action = @api.get_action(resources, args[1].to_sym, args[2..])

      unless action
        warn "Resource or action '#{args[0]} #{args[1]}' not found"
        puts
        show_help(false)
      end

      if authenticate(action) && !action.unresolved_args?
        begin
          action.update_description(@api.describe_action(action))
        rescue RestClient::ResourceNotFound => e
          format_errors(action, 'Object not found', {})
          exit(false)
        end
      end

      @selected_params = if @opts[:output]
                           @opts[:output].split(',').uniq
                         end

      @input_params = parameters(action)

      includes = build_includes(action) if @selected_params
      @input_params[:meta] = { includes: } if includes

      begin
        ret = action.execute(@input_params, raw: @opts[:raw])
      rescue HaveAPI::Client::ValidationError => e
        format_errors(action, 'input parameters not valid', e.errors)
        exit(false)
      end

      if ret[:status]
        format_output(action, ret[:response])

      else
        format_errors(action, ret[:message], ret[:errors])
        exit(false)
      end

      return unless action.blocking?

      res = HaveAPI::Client::Response.new(action, ret)

      return unless res.meta[:action_state_id]

      state = ActionState.new(
        @opts,
        HaveAPI::Client::Client.new(@api.url, communicator: @api, block: false),
        res.meta[:action_state_id]
      )

      if @opts[:block]
        puts
        action_ret = state.wait_for_completion(timeout: @opts[:timeout])

        if action_ret.nil?
          warn 'Timeout'
          exit(false)
        end

      else
        puts
        state.print_help
      end
    end

    def api_url
      @opts[:client]
    end

    def options
      options = {
          client: default_url,
          block: true,
          verbose: false
      }

      @global_opt = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options] <resource> <action> [objects ids] [-- [parameters]]"

        opts.on('-u', '--api URL', 'API URL') do |url|
          options[:client] = url
        end

        opts.on('-a', '--auth METHOD', Cli.auth_methods.keys, 'Authentication method') do |m|
          options[:auth] = m
          connect_api(url: options[:client], version: options[:version])

          @auth = Cli.auth_methods[m].new(
            @api,
            @api.describe_api(options[:version])[:authentication][m],
            server_config(options[:client])[:auth][m]
          )

          opts.separator "\nAuthentication options:"
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

        opts.on('--version VERSION', 'Use specified API version') do |v|
          options[:version] = v
        end

        opts.on('-c', '--columns', 'Print output in columns') do
          options[:layout] = :columns
        end

        opts.on('-H', '--no-header', 'Hide header row') do |_h|
          options[:header] = false
        end

        opts.on('-L', '--list-parameters', 'List output parameters') do |_l|
          options[:list_output] = true
        end

        opts.on('-o', '--output PARAMETERS', 'Parameters to display, separated by a comma') do |o|
          options[:output] = o
        end

        opts.on('-r', '--rows', 'Print output in rows') do
          options[:layout] = :rows
        end

        opts.on('-s', '--sort PARAMETER', 'Sort output by parameter') do |p|
          options[:sort] = p
        end

        opts.on('--save', 'Save credentials to config file for later use') do
          options[:save] = true
        end

        opts.on('--raw', 'Print raw response as is') do
          options[:raw] = true
        end

        opts.on('--timestamp', 'Display Datetime parameters as timestamp') do
          options[:datetime] = :timestamp
        end

        opts.on('--utc', 'Display Datetime parameters in UTC') do
          options[:datetime] = :utc
        end

        opts.on('--localtime', 'Display Datetime parameters in local timezone') do
          options[:datetime] = :local
        end

        opts.on('--date-format FORMAT', 'Display Datetime in custom format') do |f|
          options[:date_format] = f
        end

        opts.on('--[no-]block', 'Toggle action blocking mode') do |v|
          options[:block] = v
        end

        opts.on(
          '--timeout SEC',
          Float,
          'Fail when the action does not finish within the timeout'
        ) do |v|
          options[:timeout] = v.to_f
        end

        opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
          options[:verbose] = v
        end

        opts.on('--client-version', 'Show client version') do
          @action = [:show_version]
        end

        opts.on('--protocol-version', 'Show protocol version') do
          @action = [:protocol_version]
        end

        opts.on('--check-compatibility', 'Check compatibility with API server') do
          @action = [:check_compat]
        end

        opts.on('-h', '--help', 'Show this message') do
          options[:help] = true
        end
      end

      args = []

      ARGV.each do |arg|
        break if arg == '--'

        args << arg
      end

      @global_opt.parse!(args)

      unless options[:auth]
        cfg = server_config(options[:client])
        connect_api(url: options[:client], version: options[:version]) unless @api

        if m = cfg[:last_auth]
          @auth = Cli.auth_methods[m].new(
            @api,
            @api.describe_api(options[:version])[:authentication][m],
            cfg[:auth][m]
          )
        end
      end

      [args, options]
    end

    def parameters(action)
      options = {}
      sep = ARGV.index('--')

      @action_opt = OptionParser.new do |opts|
        opts.banner = ''

        if action.input
          action.input[:parameters].each do |name, p|
            opts.on(param_option(name, p), p[:description] || p[:label] || ' ') do |*args|
              arg = args.first

              options[name] = if arg.nil?
                                read_param(name, p)

                              else
                                args.first
                              end
            end
          end
        end

        opts.on('-h', '--help', 'Show this message') do
          @opts[:help] = true
        end
      end

      if @opts[:help]
        show_help do
          puts 'Action description:'
          puts action.description, "\n"
          print 'Input parameters:'
          puts @action_opt.help
          puts
          puts 'Output parameters:'

          action.params.each do |name, param|
            puts format('    %-32s %s', name, param[:description])
          end

          print_examples(action)
        end
      end

      if @opts[:list_output]
        action.params.each_key { |name| puts name }
        exit
      end

      return {} unless sep

      @action_opt.parse!(ARGV[sep + 1..])

      options
    end

    def list_versions
      desc = @api.available_versions

      desc[:versions].each_key do |v|
        next if v == :default

        v_int = v.to_s.to_i

        puts "#{v_int == desc[:default] ? '*' : ' '} v#{v}"
      end
    end

    def list_auth(v = nil)
      desc = @api.describe_api(v)

      desc[:authentication].each_key do |auth|
        puts auth if Cli.auth_methods.has_key?(auth)
      end
    end

    def list_resources(v = nil)
      desc = @api.describe_api(v)

      sort_by_key(desc[:resources]).each do |resource, children|
        nested_resource(resource, children, false)
      end
    end

    def list_actions(v = nil)
      desc = @api.describe_api(v)

      sort_by_key(desc[:resources]).each do |resource, children|
        nested_resource(resource, children, true)
      end
    end

    def show_version
      puts HaveAPI::Client::VERSION
    end

    def protocol_version
      puts HaveAPI::Client::PROTOCOL_VERSION
    end

    def check_compat
      case @api.compatible?
      when :compatible
        puts 'compatible'
        exit

      when :imperfect
        puts 'imperfect'
        exit(1)

      else
        puts 'incompatible'
        exit(2)
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

        desc[:resources].keys.sort.each do |r|
          puts "  #{r}"
        end
      end

      puts '' if !desc[:resources].empty? && !desc[:actions].empty?

      return if desc[:actions].empty?

      puts 'Actions:'

      desc[:actions].keys.sort.each do |a|
        puts "  #{a}"
      end
    end

    def nested_resource(prefix, children, actions = false)
      if actions
        children[:actions].keys.sort.each do |action|
          puts "#{prefix}##{action}"
        end
      else
        puts prefix
      end

      sort_by_key(children[:resources]).each do |resource, children|
        nested_resource("#{prefix}.#{resource}", children, actions)
      end
    end

    def show_help(exit_code = true)
      puts @global_opt.help

      if Cli.commands
        puts
        puts 'Commands:'
        Cli.commands.each do |cmd|
          puts format(
            '%-36s %s',
            "#{cmd.resource.join('.')} #{cmd.action} #{cmd.args}",
            cmd.desc
          )
        end
      end

      yield if block_given?
      exit(exit_code)
    end

    def print_examples(action)
      return if action.examples.empty?

      puts "\nExamples:\n"
      ExampleFormatter.format_examples(self, action)
    end

    def format_output(action, response, out = $>)
      if @opts[:raw]
        puts JSON.generate(response)
        return
      end

      return if response.empty? || action.output.nil?

      namespace = action.namespace(:output).to_sym

      if action.output_layout.to_sym == :custom
        return PP.pp(response[namespace], out)
      end

      cols = []

      (@selected_params || action.params.keys).each do |raw_name|
        col = {}
        name = nil
        param = nil

        # Fetching an associated attribute
        if raw_name.to_s.index('.')
          parts = raw_name.to_s.split('.').map!(&:to_sym)
          name = parts.first.to_sym

          top = action.params

          parts.each do |part|
            raise "'#{part}' not found" unless top.has_key?(part)

            if top[part][:type] == 'Resource'
              param = top[part]
              top = @api.get_action(top[part][:resource], :show, []).params

            else
              param = top[part]
              break
            end
          end

          col[:display] = proc do |r|
            next '' unless r

            top = r
            parts[1..].each do |part|
              raise "'#{part}' not found" unless top.has_key?(part)
              break if top[part].nil?

              top = top[part]
            end

            case param[:type]
            when 'Resource'
              "#{top[param[:value_label].to_sym]} (##{top[param[:value_id].to_sym]})"

            when 'Datetime'
              format_date(top)

            else
              top
            end
          end

          col[:label] = raw_name

        else # directly accessible parameter
          name = raw_name.to_sym
          param = action.params[name]
          raise "parameter '#{name}' does not exist" if param.nil?

          if param[:type] == 'Resource'
            col[:display] = proc do |r|
              next '' unless r

              "#{r[param[:value_label].to_sym]} (##{r[param[:value_id].to_sym]})"
            end

          elsif param[:type] == 'Datetime'
            col[:display] = ->(date) { format_date(date) }
          end
        end

        col.update({
            name:,
            align: %w[Integer Float].include?(param[:type]) ? 'right' : 'left'
        })

        col[:label] ||= param[:label] && !param[:label].empty? ? param[:label] : name.upcase

        cols << col
      end

      OutputFormatter.print(
        response[namespace],
        cols,
        header: @opts[:header].nil?,
        sort: @opts[:sort] && @opts[:sort].to_sym,
        layout: @opts[:layout]
      )
    end

    def header_for(action, param)
      params = action.params

      if params.has_key?(param) && params[param][:label]
        params[param][:label]
      else
        param.to_s.upcase
      end
    end

    def authenticate(action = nil)
      if @auth
        @auth.validate
        @auth.authenticate

        if @opts[:save]
          cfg = server_config(api_url)
          cfg[:auth][@opts[:auth]] = @auth.save
          cfg[:last_auth] = @opts[:auth]
          write_config
        end

      else
        # FIXME: exit as auth is needed and has not been selected
      end

      true
    end

    protected

    def default_url
      'http://localhost:4567'
    end

    def config_path
      "#{Dir.home}/.haveapi-client.yml"
    end

    def write_config
      File.write(config_path, YAML.dump(@config))
    end

    def read_config
      @config = YAML.load_file(config_path) if File.exist?(config_path)
    end

    def server_config(url)
      unless @config[:servers]
        @config[:servers] = [{ url:, auth: {} }]
        return @config[:servers].first
      end

      @config[:servers].each do |s|
        return s if s[:url] == url
      end

      @config[:servers] << { url:, auth: {} }
      @config[:servers].last
    end

    def connect_api(url: nil, version: nil)
      @api = HaveAPI::Client::Communicator.new(
        url || api_url,
        version || (@opts && @opts[:version])
      )
      @api.identity = $0.split('/').last
    end

    def format_errors(action, msg, errors)
      warn "Action failed: #{msg}"

      if errors && errors.any?
        puts 'Errors:'
        errors.each do |param, e|
          puts "\t#{param}: #{e.join('; ')}"
        end
      end

      puts "\nUse --help to see available parameters and example usage."
    end

    def find_command(resource, action)
      return false unless Cli.commands

      Cli.commands.each do |cmd|
        return cmd if cmd.handle?(resource, action)
      end

      false
    end

    # Translate requested parameters into meta[includes] that is sent
    # to the API.
    #
    # When using haveapi-cli vps list -o
    #   node.location => node__location
    #   node.location.domain => node_location
    #   node.name => node
    def build_includes(action)
      ret = []

      @selected_params.each do |param|
        next unless param.index('.')

        includes = []
        top = action.params

        param.split('.').map!(&:to_sym).each do |part|
          next unless top.has_key?(part)
          next if top[part][:type] != 'Resource'

          includes << part
          top = @api.get_action(top[part][:resource], :show, []).params
        end

        ret << includes.join('__')
      end

      ret.uniq!
      ret.empty? ? nil : ret.join(',')
    end

    def format_date(date)
      return '' unless date

      t = DateTime.iso8601(date).to_time
      ret = case @opts[:datetime]
            when :timestamp
              t.to_i

            when :utc
              t.utc

            when :local
              t.localtime

            else
              t.localtime
            end

      @opts[:date_format] ? ret.strftime(@opts[:date_format]) : ret
    end

    def sort_by_key(hash)
      hash.sort do |a, b|
        a[0] <=> b[0]
      end
    end
  end
end
