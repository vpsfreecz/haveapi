require 'pp'
require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class RubyClient < HaveAPI::ClientExample
    label 'Ruby'
    language 'ruby'
    language_label 'Ruby'
    code :ruby
    order 0

    def self.detail_levels_for(kind, context:, result:, auth_method: nil, auth_description: nil)
      result[:status] == :limitation || (kind == :auth && auth_method == :oauth2) ? SIMPLE_DETAIL_LEVELS : DEFAULT_DETAIL_LEVELS
    end

    def initialization
      "require 'haveapi/client'\n\napi = HaveAPI::Client.new(#{base_url.dump}, version: #{version.to_s.dump})\n"
    end

    def with_error_handling(body)
      <<~RUBY
        begin
        #{body.lines.map { |line| line == "\n" ? line : "  #{line}" }.join.chomp}
        rescue HaveAPI::Client::ValidationError => error
          warn error.message
          warn error.errors.inspect
        rescue HaveAPI::Client::ActionFailed => error
          warn error.message
          warn error.response.errors.inspect if error.response.is_a?(HaveAPI::Client::Response)
        rescue HaveAPI::Client::Authentication::AuthenticationFailed, HaveAPI::Client::ProtocolError,
               RestClient::Exception, JSON::ParserError => error
          warn error.message
        end
      RUBY
    end

    def init
      thorough? ? with_error_handling("#{initialization}api.setup\n") : initialization
    end

    def auth_login_literal(name, parameter, value)
      return value unless value == false || value.nil?

      # Token#request_token copies only truthy login options.
      auth_literal(name, parameter, excluding: [false, nil])
    end

    def auth(method, desc)
      body = case method
             when :basic
               "api.authenticate(:basic, user: 'user', password: 'secret')"
             when :token
               input = auth_token_credentials(desc).transform_keys(&:to_sym)
               continuations = auth_token_continuations(desc)
               code = "api.authenticate(:token, **#{input.inspect})"
               unless continuations.empty?
                 code << <<~RUBY
                    do |action, parameters|
                     continuations = #{continuations.inspect}
                     input = continuations.fetch(action.to_s) { raise ArgumentError, 'Unknown authentication continuation' }
                     unless (parameters.keys.map(&:to_s) - input.keys - ['token']).empty?
                       raise ArgumentError, 'Unknown authentication input'
                     end
                     input.transform_keys(&:to_sym)
                   end
                 RUBY
               end
               %(#{code.chomp}\n\n# Reuse an existing token\napi.authenticate(:token, token: 'example-token'))
             when :oauth2
               return '# OAuth2 is not supported by HaveAPI Ruby client.'
             end
      return unless body

      source = [initialization.chomp, (thorough? ? 'api.setup' : nil), body].compact.join("\n\n")
      thorough? ? with_error_handling(source) : source
    rescue HaveAPI::ClientExample::UnsupportedAuthentication => e
      { status: :limitation, reason: e.message }.freeze
    end

    def action_authentication
      return '' unless action[:auth] && context

      providers = auth_field(context.description, :authentication, {}).keys.map(&:to_s)
      return "api.authenticate(:token, token: 'example-token')\n" if providers.include?('token')
      return "api.authenticate(:basic, user: 'user', password: 'secret')\n" if providers.include?('basic')

      raise HaveAPI::ClientExample::UnsupportedAuthentication, 'This action requires authentication unsupported by this client.'
    end

    def example(sample)
      credentials = action_authentication
      args = []

      args.concat(sample[:path_params]) if sample[:path_params]

      if sample[:request] && !sample[:request].empty?
        args << PP.pp(sample[:request], '').strip
      end

      out = +''
      out << "reply = api.#{resource_path.join('.')}.#{action_name}"
      out << "(#{args.join(', ')})" unless args.empty?

      out << if sample[:status]
               response(sample)
             else
               "\n# Raises exception HaveAPI::Client::ActionFailed\n"
             end
      thorough? ? with_error_handling(["#{initialization}api.setup", credentials.chomp, out].reject(&:empty?).join("\n\n")) : out
    rescue HaveAPI::ClientExample::UnsupportedAuthentication => e
      { status: :limitation, reason: e.message }.freeze
    end

    def response(sample)
      out = "\n\n"

      case action[:output][:layout]
      when :hash
        out << "# reply is an instance of HaveAPI::Client::Response\n"
        out << "# reply.response() returns a hash of output parameters:\n"
        out << PP.pp(sample[:response] || {}, '').split("\n").map { |v| "# #{v}" }.join("\n")

      when :hash_list
        out << "# reply is an instance of HaveAPI::Client::Response\n"
        out << "# reply.response() returns an array of hashes:\n"
        out << PP.pp(sample[:response] || [], '').split("\n").map { |v| "# #{v}" }.join("\n")

      when :object
        out << "# reply is an instance of HaveAPI::Client::ResourceInstance\n"

        (sample[:response] || {}).each do |pn, pv|
          param = action[:output][:parameters][pn]

          if param[:type] == 'Resource'
            out << "# reply.#{pn} = HaveAPI::Client::ResourceInstance("
            out << "resource: #{param[:resource].join('.')}, "

            out << if pv.is_a?(::Hash)
                     pv.map { |k, v| "#{k}: #{PP.pp(v, '').strip}" }.join(', ')
                   else
                     "id: #{pv}"
                   end

            out << ")\n"

          else
            out << "# reply.#{pn} = #{PP.pp(pv, '')}"
          end
        end

      when :object_list
        out << "# reply is an instance of HaveAPI::Client::ResourceInstanceList,\n"
        out << '# which is a subclass of Array'
      end

      out
    end
  end
end
