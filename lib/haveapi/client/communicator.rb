require 'rest_client'
require 'json'
require 'active_support/inflections'
require 'active_support/inflector'
require_rel '../../restclient_ext'

module HaveAPI
  module Client
    class Communicator
      class << self
        attr_reader :auth_methods

        def register_auth_method(name, klass)
          @auth_methods ||= {}
          @auth_methods[name] = klass
        end
      end

      attr_reader :url

      def initialize(url, v = nil)
        @url = url
        @auth = Authentication::NoAuth.new(self, {}, {})
        @rest = RestClient::Resource.new(@url)
        @version = v
      end

      # Authenticate user with selected +auth_method+.
      # +auth_method+ is a name of registered authentication provider.
      # +options+ are specific for each authentication provider.
      def authenticate(auth_method, options = {})
        desc = describe_api(@version)
        desc = desc[:versions][desc[:default_version].to_s.to_sym] unless @version

        @auth = self.class.auth_methods[auth_method].new(self, desc[:authentication][auth_method], options)
        @rest = @auth.resource || @rest
      end

      def auth_save
        @auth.save
      end

      def describe_api(v=nil)
        description_for(path_for(v))
      end

      def describe_resource(path)
        api = describe_api
        tmp = api[:versions][ api[:default_version].to_s.to_sym ]

        path.each do |r|
          tmp = tmp[:resources][r.to_sym]

          return false unless tmp
        end

        tmp
      end

      def describe_action(action)
        description_for(action.prepared_help)
      end

      def get_action(resources, action, args)
        @spec ||= describe_api(@version)
        @spec = @spec[:versions][@spec[:default_version].to_s.to_sym] unless @version

        tmp = @spec

        resources.each do |r|
          tmp = tmp[:resources][r.to_sym]

          return false unless tmp
        end

        a = tmp[:actions][action]

        if a
          Action.new(self, action, a, args)
        else
          false
        end
      end

      def call(action, params, raw: false)
        args = []
        input_namespace = action.namespace(:input)

        if %w(POST PUT).include?(action.http_method)
          args << {input_namespace => params}.update(@auth.request_payload).to_json
          args << {:content_type => :json, :accept => :json}.update(@auth.request_headers)

        elsif %w(GET DELETE).include?(action.http_method)
          get_params = {}

          params.each do |k, v|
            get_params["#{input_namespace}[#{k}]"] = v
          end

          args << {params: get_params.update(@auth.request_url_params), accept: :json}.update(@auth.request_headers)
        end

        begin
          response = parse(@rest[action.prepared_url].method(action.http_method.downcase.to_sym).call(*args))

        rescue RestClient::Forbidden
          return error('Access forbidden. Bad user name or password? Not authorized?')

        rescue => e
          return error("Fatal API error: #{e.inspect}")
        end

        if response[:status]
          if raw
            ok(JSON.pretty_generate(response[:response]))
          else
            ok(response[:response])
          end

        else
          error(response[:message], response[:errors])
        end
      end

      private
        def ok(response)
          {status: true, response: response}
        end

        def error(msg, errors={})
          {status: false, message: msg, errors: errors}
        end

        def path_for(v=nil, r=nil)
          ret = '/'

          ret += "v#{v}/" if v
          ret += r if r

          ret
        end

        def description_for(path)
          parse(@rest[path].get_options({params: @auth.request_payload.update(@auth.request_url_params)}.update(@auth.request_headers)))
        end

        def parse(str)
          JSON.parse(str, symbolize_names: true)
        end
    end
  end
end
