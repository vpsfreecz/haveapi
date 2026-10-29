require 'spec_helper'

describe HaveAPI::Authentication::OAuth2::Provider do
  let(:server) { instance_double(HaveAPI::Server, allow_header: nil) }
  let(:provider) { described_class.new(server, 1, HaveAPI::Authentication::OAuth2::Config) }
  let(:request) do
    env = Rack::MockRequest.env_for(
      'https://docs.example/v1/?access_token=query-token',
      'HTTP_AUTHORIZATION' => 'Bearer api-token', 'HTTP_X_HAVEAPI_OAUTH2_TOKEN' => 'custom-token'
    )
    Rack::Request.new(env)
  end

  it 'validates the supplied token with the original request without extracting or mutating API credentials' do
    request.params
    original = request.env.dup
    user = Object.new
    allow(provider.config).to receive(:find_user_by_access_token).with(request, 'cookie-token').and_return(user)

    expect(provider.authenticate_access_token(request, 'cookie-token')).to equal(user)
    expect(provider.config).to have_received(:find_user_by_access_token).once
    expect(request.env).to eq(original)
    expect(request.params).to eq('access_token' => 'query-token')
  end

  it 'retains ordinary multiple-token conflict handling before backend lookup' do
    allow(provider.config).to receive(:find_user_by_access_token)
    expect { provider.authenticate(request) }.to raise_error(HaveAPI::Authentication::TokenConflict)
    expect(provider.config).not_to have_received(:find_user_by_access_token)
  end

  it 'converts only the existing authentication error into a failed token lookup' do
    allow(provider.config).to receive(:find_user_by_access_token).and_raise(HaveAPI::AuthenticationError)
    expect(provider.authenticate_access_token(request, 'cookie-token')).to be_nil
    allow(provider.config).to receive(:find_user_by_access_token).and_raise(TypeError, 'backend contract error')
    expect { provider.authenticate_access_token(request, 'cookie-token') }.to raise_error(TypeError, 'backend contract error')
  end
end
