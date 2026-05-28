# frozen_string_literal: true

module ServerIntegrationSpec
  module State
    class << self
      def reset!
        writes.clear
      end

      def writes
        @writes ||= []
      end
    end
  end
end

describe HaveAPI::Server do
  describe 'integration' do
    api do
      define_resource(:Test) do
        version 1
        auth false

        define_action(:Echo) do
          http_method :post
          authorize { allow }

          input do
            string :msg
          end

          output do
            string :msg
          end

          def exec
            { msg: params.dig(:test, :msg) }
          end
        end

        define_action(:AuthorizeError) do
          route 'authorize_error'
          http_method :get

          authorize do
            raise 'authorize boom'
          end

          def exec
            ok!
          end
        end
      end

      define_resource(:Transfer) do
        version 1
        auth false

        define_action(:Create) do
          route ''
          http_method :post
          authorize { allow }

          input(:hash) do
            integer :amount, required: true
          end

          output(:hash) do
            bool :created
          end

          def exec
            ServerIntegrationSpec::State.writes << input[:amount]
            { created: true }
          end
        end
      end
    end

    default_version 1

    before do
      ServerIntegrationSpec::State.reset!
    end

    it 'returns 406 for unsupported Accept' do
      header 'Accept', 'text/plain'
      options '/v1/'

      expect(last_response.status).to eq(406)
    end

    it 'returns 400 for invalid JSON' do
      header 'Content-Type', 'application/json'
      header 'Accept', 'application/json'
      post '/v1/tests/echo', '{'

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.message).to match(/Bad JSON syntax/)
    end

    it 'returns 400 for non-object JSON bodies' do
      header 'Content-Type', 'application/json'
      header 'Accept', 'application/json'

      ['[]', '"msg"', '123', 'true', 'null'].each do |body|
        post '/v1/tests/echo', body

        expect(last_response.status).to eq(400)
        expect(api_response).not_to be_ok
        expect(api_response.message).to eq('JSON body must be an object')
      end
    end

    it 'does not accept query-string input for non-GET actions' do
      header 'Accept', 'application/json'
      post '/v1/transfers?transfer[amount]=250', nil, {
        'CONTENT_TYPE' => 'application/x-www-form-urlencoded'
      }

      expect(last_response.status).to eq(200)
      expect(api_response).not_to be_ok
      expect(ServerIntegrationSpec::State.writes).to be_empty
    end

    it 'rejects non-JSON content types for JSON action bodies' do
      header 'Accept', 'application/json'
      post '/v1/transfers', '{"transfer":{"amount":250}}', {
        'CONTENT_TYPE' => 'text/plain'
      }

      expect(last_response.status).to eq(415)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('Unsupported Content-Type')
      expect(ServerIntegrationSpec::State.writes).to be_empty
    end

    it 'returns 400 for malformed Accept headers' do
      invalid_accept = (+"\xFF").force_encoding(Encoding::UTF_8)
      header 'Accept', invalid_accept
      header 'Content-Type', 'application/json'

      post '/v1/tests/echo', '{}'

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('Bad Accept header')
    end

    it 'returns JSON envelope for unknown route' do
      header 'Accept', 'application/json'
      get '/does-not-exist'

      expect(last_response.status).to eq(404)
      expect(api_response).not_to be_ok
    end

    it 'routes request-level exceptions through hook' do
      calls = []

      app.settings.api_server.connect_hook(:request_exception) do |ret, context, exception|
        calls << [context, exception]
        ret
      end

      header 'Accept', 'application/json'
      get '/v1/tests/authorize_error'

      expect(last_response.status).to eq(500)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('Server error occurred')

      expect(calls.size).to eq(1)
      context, exception = calls.first
      expect(context.action.to_s).to include('AuthorizeError')
      expect(exception.message).to eq('authorize boom')
    end

    it 'handles CORS preflight OPTIONS' do
      header 'Accept', 'application/json'
      header 'Origin', 'https://example.com'
      header 'Access-Control-Request-Method', 'POST'
      header 'Access-Control-Request-Headers', 'X-Foo, Authorization'
      options '/v1/'

      expect(last_response.status).to eq(200)

      headers = last_response.headers.transform_keys(&:downcase)
      expect(headers['access-control-allow-origin']).to eq('*')
      expect(headers['access-control-allow-methods']).to include('POST')
      expect(headers['access-control-allow-headers']).to be_a(String)
    end
  end
end
