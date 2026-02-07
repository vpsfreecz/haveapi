# frozen_string_literal: true

describe 'Server integration' do
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
    end
  end

  default_version 1

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

  it 'returns JSON envelope for unknown route' do
    header 'Accept', 'application/json'
    get '/does-not-exist'

    expect(last_response.status).to eq(404)
    expect(api_response).not_to be_ok
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
