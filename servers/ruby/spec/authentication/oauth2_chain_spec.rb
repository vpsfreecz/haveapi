require 'spec_helper'

describe HaveAPI::Authentication::Chain do
  let(:server) { instance_double(HaveAPI::Server, add_auth_routes: nil) }
  let(:chain) { described_class.new(server) }
  let(:request) { Rack::Request.new(Rack::MockRequest.env_for('https://docs.example/v1/?access_token=api-token')) }
  let(:calls) { [] }

  def provider(name, result: nil, token_validation: true, deny_token: false)
    recorded = calls
    Class.new(HaveAPI::Authentication::Base) do
      auth_method name
      define_method(:authenticate) do |req|
        recorded << [:ordinary, @version, req]
        result
      end
      if token_validation
        define_method(:authenticate_access_token) do |req, token|
          recorded << [:cookie, @version, req, token]
          deny if deny_token
          result
        end
      end
    end
  end

  it 'validates only the requested version OAuth providers in registration order' do
    chain[1] << provider(:basic, result: :basic_user)
    chain[1] << provider(:oauth2)
    chain[1] << provider(:token, result: :token_user)
    chain[1] << provider(:oauth2, result: :cookie_user)
    chain[1] << provider(:oauth2, result: :unused_user)
    chain[2] << provider(:oauth2, result: :other_version)
    chain.setup([1, 2])

    expect(chain.authenticate_oauth2_token(1, request, 'cookie-token')).to eq(:cookie_user)
    expect(calls).to eq([[:cookie, 1, request, 'cookie-token'], [:cookie, 1, request, 'cookie-token']])
    calls.clear
    expect(chain.authenticate_oauth2_token(2, request, 'cookie-token')).to eq(:other_version)
    expect(calls).to eq([[:cookie, 2, request, 'cookie-token']])
  end

  it 'fails closed for a custom oauth2 provider without explicit token validation' do
    chain[1] << provider(:oauth2, result: :ordinary_user, token_validation: false)
    chain[1] << provider(:basic, result: :basic_user)
    chain.setup([1])

    expect(chain.authenticate_oauth2_token(1, request, 'cookie-token')).to be_nil
    expect(calls).to be_empty
    expect(chain.authenticate(1, request)).to eq(:ordinary_user)
    expect(calls).to eq([[:ordinary, 1, request]])
  end

  it 'preserves provider deny semantics instead of trying a later OAuth provider' do
    chain[1] << provider(:oauth2, deny_token: true)
    chain[1] << provider(:oauth2, result: :later_user)
    chain.setup([1])

    expect(chain.authenticate_oauth2_token(1, request, 'cookie-token')).to be_nil
    expect(calls).to eq([[:cookie, 1, request, 'cookie-token']])
  end

  it 'does not authenticate another version or ordinary provider when OAuth is unavailable' do
    chain[1] << provider(:basic, result: :basic_user)
    chain[2] << provider(:oauth2, result: :other_user)
    chain.setup([1, 2])

    expect(chain.authenticate_oauth2_token(1, request, 'cookie-token')).to be_nil
    expect(chain.authenticate_oauth2_token(3, request, 'cookie-token')).to be_nil
    expect(calls).to be_empty
  end
end
