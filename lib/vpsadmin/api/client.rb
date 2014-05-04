require 'rest_client'
require 'json'
require 'active_support/inflections'
require_rel '../../restclient_ext'

module VpsAdmin
  module API
    class Client
      def initialize(url)
        @url = url
        @rest = RestClient::Resource.new(@url)
        @version = 1
      end

      def login(user, password)
        @rest = RestClient::Resource.new(@url, user, password)
      end

      def describe_api(v=nil)
        description_for(path_for(v))
      end

      def describe_action(v, r)

      end

      def get_action(resources, action, args)
        @spec ||= describe_api(@version)

        tmp = @spec

        resources.each do |r|
          tmp = tmp[:resources][r.to_sym]

          return false unless tmp
        end

        a = tmp[:actions][action]

        if a
          Action.new(self, a, args)
        else
          false
        end
      end

      def call(action, raw: false)
        begin
          response = parse(@rest[action.url].method(action.http_method.downcase.to_sym).call)

        rescue RestClient::Forbidden
          return error('Access forbidden. Bad user name or password?')

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
          error(response[:message])
        end
      end

      private
        def ok(response)
          {status: true, response: response}
        end

        def error(msg)
          {status: false, message: msg}
        end

        def path_for(v=nil, r=nil)
          ret = '/'

          ret += "v#{v}/" if v
          ret += r if r

          ret
        end

        def description_for(path)
          parse(@rest[path].get_options)
        end

        def parse(str)
          JSON.parse(str, symbolize_names: true)
        end
    end
  end
end
