require 'spec_helper'

describe HaveAPI::DocumentationOAuth::Transport do
  let(:uri) { URI('https://issuer.example/token') }
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPOK, code: '200') }

  before do
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:max_retries=)
    allow(http).to receive(:request).and_yield(response)
    allow(response).to receive(:read_body).and_yield('{}')
  end

  it 'requires verified HTTPS with bounded timeouts and sends credentials only in the body' do
    expect(described_class.new.post(uri, 'client_secret' => 'private')).to eq('{}')
    expect(Net::HTTP).to have_received(:start).with('issuer.example', 443,
                                                    use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER,
                                                    open_timeout: 5, read_timeout: 10, write_timeout: 10)
    expect(http).to have_received(:max_retries=).with(0)
    expect(http).to have_received(:request) do |request|
      expect(request.uri.to_s).to eq('https://issuer.example/token')
      expect(request.body).to eq('client_secret=private')
    end
  end

  it 'rejects redirects without following them or exposing their body' do
    allow(response).to receive(:code).and_return('302')
    allow(response).to receive(:read_body).and_yield('PRIVATE_PROVIDER_BODY')
    expect { described_class.new.post(uri, {}) }.to raise_error(HaveAPI::DocumentationOAuth::Failure, 'Documentation OAuth request failed')
    expect(http).to have_received(:request).once
  end

  it 'bounds the body while streaming rather than reading an unbounded response' do
    allow(response).to receive(:read_body).and_yield('x' * 8192).and_yield('x' * 8193)
    expect { described_class.new.post(uri, {}) }.to raise_error(HaveAPI::DocumentationOAuth::Failure)
  end

  it 'converts TLS and DNS failures into generic authentication failure' do
    [OpenSSL::SSL::SSLError.new('PRIVATE_TLS_DETAIL'), SocketError.new('PRIVATE_DNS_DETAIL')].each do |error|
      allow(Net::HTTP).to receive(:start).and_raise(error)
      expect { described_class.new.post(uri, {}) }.to raise_error(HaveAPI::DocumentationOAuth::Failure, 'Documentation OAuth request failed')
    end
  end
end
