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
      attr_accessor :identity

      def initialize(url, v = nil)
        @url = url
        @auth = Authentication::NoAuth.new(self, {}, {})
        @rest = RestClient::Resource.new(@url)
        @version = v
        @identity = 'haveapi-client-ruby'
        @desc = {}
      end

      # Authenticate user with selected +auth_method+.
      # +auth_method+ is a name of registered authentication provider.
      # +options+ are specific for each authentication provider.
      def authenticate(auth_method, options = {})
        desc = describe_api(@version)

        @auth = self.class.auth_methods[auth_method].new(self, desc[:authentication][auth_method], options)
        @rest = @auth.resource || @rest
      end

      def auth_save
        @auth.save
      end

      def available_versions
        description_for(path_for, {describe: :versions})
      end

      def describe_api(v=nil)
        return @desc[v] if @desc.has_key?(v)

        @desc[v] = description_for(path_for(v), v.nil? ? {describe: :default} : {})
      end

      def describe_resource(path)
        tmp = describe_api(@version)

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
        tmp = describe_api(@version)

        resources.each do |r|
          tmp = tmp[:resources][r.to_sym]

          return false unless tmp
        end

        a = tmp[:actions][action]

        if a
          obj = Action.new(self, action, a, args)
          obj.resource_path = resources
          obj
        else
          false
        end
      end

      def call(action, params, raw: false)
        args = []
        input_namespace = action.namespace(:input)
        meta = nil

        if params[:meta]
          meta = params[:meta]
          params.delete(:meta)
        end

        if %w(POST PUT).include?(action.http_method)
          ns = {input_namespace => params}
          ns[:_meta] = meta if meta
          ns.update(@auth.request_payload)

          args << ns.to_json
          args << {content_type: :json, accept: :json, user_agent: @identity}.update(@auth.request_headers)

        elsif %w(GET DELETE).include?(action.http_method)
          get_params = {}

          params.each do |k, v|
            get_params["#{input_namespace}[#{k}]"] = v
          end

          meta.each do |k, v|
            get_params["_meta[#{k}]"] = v # FIXME: read _meta namespace from the description

          end if meta

          args << {params: get_params.update(@auth.request_url_params), accept: :json, user_agent: @identity}.update(@auth.request_headers)
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

        def description_for(path, query_params={})
          parse(@rest[path].get_options({
              params: @auth.request_payload.update(@auth.request_url_params).update(query_params),
              user_agent: @identity
          }.update(@auth.request_headers)))[:response]
        end

        def parse(str)
          JSON.parse(str, symbolize_names: true)
        end
    end
  end
end
