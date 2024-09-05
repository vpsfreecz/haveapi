require 'rest-client'
require 'json'
require 'active_support/inflections'
require 'active_support/inflector'
require_rel '../../restclient_ext'

module HaveAPI::Client
  class Communicator
    class << self
      attr_reader :auth_methods

      def register_auth_method(name, klass)
        @auth_methods ||= {}
        @auth_methods[name] = klass
      end
    end

    attr_reader :url, :auth
    attr_accessor :identity

    def initialize(url, v = nil)
      @url = url
      @auth = Authentication::NoAuth.new(self, {}, {})
      @rest = RestClient::Resource.new(@url)
      @version = v
      @identity = 'haveapi-client-ruby'
    end

    def inspect
      "#<#{self.class.name} @url=#{@url} @version=#{@version} @auth=#{@auth.class.name}>"
    end

    # @return [:compatible] if perfectly compatible
    # @return [:imperfect] if minor version differs
    # @return [false] if not compatible
    def compatible?
      description_for(path_for, { describe: :versions })
      if @proto_version == HaveAPI::Client::PROTOCOL_VERSION
        :compatible
      else
        :imperfect
      end
    rescue ProtocolError
      false
    end

    # Authenticate user with selected +auth_method+.
    # +auth_method+ is a name of registered authentication provider.
    # +options+ are specific for each authentication provider.
    def authenticate(auth_method, options = {}, &block)
      desc = describe_api(@version)

      @auth = self.class.auth_methods[auth_method].new(
        self,
        desc[:authentication][auth_method],
        options,
        &block
      )
      @rest = @auth.resource || @rest
    end

    def auth_save
      @auth.save
    end

    def available_versions
      description_for(path_for, { describe: :versions })
    end

    def describe_api(v = nil)
      description_for(path_for(v), v.nil? ? { describe: :default } : {})
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

      unless a # search in aliases
        tmp[:actions].each_value do |v|
          if v[:aliases].include?(action.to_s)
            a = v
            break
          end
        end
      end

      if a
        obj = Action.new(nil, self, action, a, args)
        obj.resource_path = resources
        obj
      else
        false
      end
    end

    def call(action, params = {}, raw: false)
      args = []
      input_namespace = action.input && action.namespace(:input)
      meta = nil

      if params.is_a?(Hash) && params[:meta]
        meta = params[:meta]
        params.delete(:meta)
      end

      if %w[POST PUT].include?(action.http_method)
        ns = {}
        ns[input_namespace] = params if input_namespace
        ns[:_meta] = meta if meta
        ns.update(@auth.request_payload)

        args << ns.to_json
        args << { content_type: :json, accept: :json, user_agent: @identity }.update(@auth.request_headers)

      elsif %w[GET DELETE].include?(action.http_method)
        get_params = {}

        params.each do |k, v|
          get_params["#{input_namespace}[#{k}]"] = v
        end

        if meta
          meta.each do |k, v|
            get_params["_meta[#{k}]"] = v # FIXME: read _meta namespace from the description
          end
        end

        args << { params: get_params.update(@auth.request_query_params), accept: :json, user_agent: @identity }.update(@auth.request_headers)
      end

      begin
        response = parse(@rest[action.prepared_path].method(action.http_method.downcase.to_sym).call(*args))
      rescue RestClient::Forbidden
        return error('Access forbidden. Bad user name or password? Not authorized?')
      rescue RestClient::ResourceNotFound,
             RestClient::BadRequest => e
        response = parse(e.http_body)
      rescue StandardError => e
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
      { status: true, response: response }
    end

    def error(msg, errors = {})
      { status: false, message: msg, errors: errors }
    end

    def path_for(v = nil, r = nil)
      ret = '/'

      ret += "v#{v}/" if v
      ret += r if r

      ret
    end

    def description_for(path, query_params = {})
      ret = parse(@rest[path].get_options({
          params: @auth.request_payload.update(@auth.request_query_params).update(query_params),
          user_agent: @identity
      }.update(@auth.request_headers)))

      @proto_version = ret[:version]
      p_v = HaveAPI::Client::PROTOCOL_VERSION
      return ret[:response] if ret[:version] == p_v

      unless ret[:version]
        raise ProtocolError,
              "Incompatible protocol version: the client uses v#{p_v} while the API server uses an unspecified version (pre 1.0)"
      end

      major1, minor1 = ret[:version].split('.')
      major2, minor2 = p_v.split('.')

      if major1 != major2
        raise ProtocolError,
              "Incompatible protocol version: the client uses v#{p_v} " \
              "while the API server uses v#{ret[:version]}"
      end

      warn "The client uses protocol v#{p_v} while the API server uses v#{ret[:version]}"
      ret[:response]
    end

    def parse(str)
      JSON.parse(str, symbolize_names: true)
    end
  end
end
