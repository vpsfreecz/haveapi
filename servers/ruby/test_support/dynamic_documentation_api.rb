require 'json'
require_relative '../lib/haveapi'

module DynamicDocumentationAPI
  PAYLOAD = { 'text' => "DOC_LITERAL žluťoučký \"quote\"\\\n</script>",
              '__proto__' => { 'constructor' => [false, 0, nil, ''] } }.freeze
  def self.receipts
    @receipts ||= []
  end
  User = Struct.new(:login)

  class RequestTrace
    def initialize(app, output: $stderr)
      @app = app
      @output = output
    end

    def call(env)
      status, headers, body = @app.call(env)
      @output.puts("DYNAMIC_DOCUMENTATION_REQUEST #{JSON.generate({ method: env['REQUEST_METHOD'], path: env['PATH_INFO'], status: })}")
      [status, headers, body]
    end
  end

  class BasicProvider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(username) if username == 'fixture-user' && password == 'fixture-password'
    end
  end

  class TokenConfig < HaveAPI::Authentication::Token::Config
    request do
      handle do |request, result|
        if request.input[:user] == 'fixture-user' && request.input[:password] == 'fixture-password'
          result.token = 'fixture-challenge'
          result.next_action = 'verify'
          result.complete = false
          result.valid_to = Time.now + 3600
          result.ok
        else
          result.error = 'Invalid fixture credentials'
          result
        end
      end
    end

    action :verify do
      input { string :code, required: true }
      handle do |request, result|
        if request.token == 'fixture-challenge' && request.input[:code] == '123456'
          result.token = 'fixture-token'
          result.complete = true
          result.valid_to = Time.now + 3600
          result.ok
        else
          result.error = 'Invalid fixture challenge'
          result
        end
      end
    end

    renew { handle { |_request, result| result.ok } }
    revoke { handle { |_request, result| result.ok } }

    def find_user_by_token(_request, token)
      User.new('fixture-user') if token == 'fixture-token'
    end
  end

  TokenProvider = HaveAPI::Authentication::Token.with_config(TokenConfig)

  class OAuth2Provider < HaveAPI::Authentication::Base
    auth_method :oauth2

    def describe
      { http_header: 'X-Fixture-OAuth2' }
    end

    def authenticate(request)
      value = request.env['HTTP_X_FIXTURE_OAUTH2'] || request.env['HTTP_AUTHORIZATION']&.delete_prefix('Bearer ')
      User.new('fixture-user') if value == 'fixture-access-token'
    end
  end

  module Resources
    class Constructor < HaveAPI::Resource
      version '2'
      route 'parents'

      class Resources < HaveAPI::Resource
        route '{parent_id}/children'

        class New < HaveAPI::Action
          route '{widget_id}'
          http_method :post
          auth true
          authorize { |user| user ? allow : deny }

          input(:hash, namespace: :widget) do
            string :name
            bool :enabled
            integer :count
            string :nullable, nullable: true
            string :omitted
            custom :payload
          end

          output(:hash, namespace: :widget) do
            string :marker
            custom :payload
          end

          example 'literal success' do
            path_params 7, 'name with space'
            request(name: '', enabled: false, count: 0, nullable: nil, payload: DynamicDocumentationAPI::PAYLOAD)
            response(marker: 'DOC_SUCCESS', payload: DynamicDocumentationAPI::PAYLOAD)
          end

          example 'literal failure' do
            path_params 7, 'name with space'
            request(name: '', enabled: false, count: -1, nullable: nil, payload: DynamicDocumentationAPI::PAYLOAD)
            status false
            message 'DOC_FAILURE'
            errors count: ['DOC_FAILURE']
          end
          def exec
            DynamicDocumentationAPI.receipts << { path: path_params.values_at('parent_id', 'widget_id'), input: }
            error!('DOC_FAILURE', { count: ['DOC_FAILURE'] }, http_status: 400) if input[:count] < 0

            { marker: 'DOC_SUCCESS', payload: input[:payload] }
          end
        end
      end
    end
  end

  def self.build
    HaveAPI.implicit_version = '2'
    api = HaveAPI::Server.new(Resources)
    api.use_version('2')
    api.default_version = '2'
    api.auth_chain << BasicProvider
    api.auth_chain << TokenProvider
    api.auth_chain << OAuth2Provider
    api.connect_hook(:pre_mount) do |ret, _server, sinatra|
      sinatra.get '/__acceptance_receipts' do
        content_type 'application/json'
        JSON.generate(DynamicDocumentationAPI.receipts)
      end
      ret
    end
    api.mount('/mount/')
    api
  end
end

if $0 == __FILE__
  require 'webrick'
  require 'rackup'
  server = nil
  trap('TERM') { server&.shutdown }
  app = DynamicDocumentationAPI::RequestTrace.new(DynamicDocumentationAPI.build.app)
  Rackup::Handler::WEBrick.run(app, Host: '127.0.0.1', Port: 0,
                                    AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)) do |instance|
    server = instance
    puts "DYNAMIC_DOCUMENTATION_READY http://127.0.0.1:#{server.listeners.first.addr[1]}"
    $stdout.flush
  end
end
