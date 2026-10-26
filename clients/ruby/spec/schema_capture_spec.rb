require_relative 'schema_spec_helper'

RSpec.describe HaveAPI::Schema::Capture do
  include SchemaFixtures

  before do
    stub_const('RestClient::Request', Class.new)
    allow(described_class).to receive(:require).with('rest-client').and_return(true)
    allow(RestClient::Request).to receive(:execute).and_return(double(code: 200, to_s: JSON.generate(envelope)))
  end

  def fetch(**options)
    described_class.fetch(url: SchemaFixtures::URL, api_version: '7.0', profile: 'fixture', **options)
  end

  it 'requests only the exact mounted version URL with bounded TLS-verified OPTIONS' do
    expect(fetch).to eq(snapshot)
    expect(RestClient::Request).to have_received(:execute).once.with(
      method: :options, url: SchemaFixtures::URL, headers: { accept: :json },
      verify_ssl: true, max_redirects: 0, open_timeout: 10, read_timeout: 30
    )
  end

  it 'uses HTTP Basic credentials without discovery or query parameters' do
    fetch(basic_user: 'fixture-user', basic_password: 'fixture-password')
    expect(RestClient::Request).to have_received(:execute).once.with(hash_including(
                                                                       url: SchemaFixtures::URL, user: 'fixture-user', password: 'fixture-password',
                                                                       headers: { accept: :json }
                                                                     ))
  end

  it 'discovers token policy anonymously at the same URL and saves only the authorized surface' do
    anonymous = envelope
    anonymous['response']['authentication'] = { 'token' => { 'http_header' => 'X-Capture-Token' } }
    authorized = Marshal.load(Marshal.dump(anonymous))
    authorized['response']['resources'] = { 'authorized' => { 'resources' => {}, 'actions' => {} } }
    allow(RestClient::Request).to receive(:execute).and_return(
      double(code: 200, to_s: JSON.generate(anonymous)),
      double(code: 200, to_s: JSON.generate(authorized))
    )
    provider = double(request_headers: { 'X-Capture-Token' => 'fixture-token' })
    stub_const('HaveAPI::Client::Authentication::Token', Class.new)
    allow(described_class).to receive(:require).with('haveapi/client').and_return(true)
    allow(HaveAPI::Client::Authentication::Token).to receive(:new)
      .with(nil, { http_header: 'X-Capture-Token' }, token: 'fixture-token').and_return(provider)
    requests = []
    allow(RestClient::Request).to receive(:execute).and_wrap_original do |_original, options|
      requests << options
      body = requests.length == 1 ? anonymous : authorized
      double(code: 200, to_s: JSON.generate(body))
    end
    result = fetch(token: 'fixture-token')
    expect(HaveAPI::Client::Authentication::Token).to have_received(:new)
      .with(nil, { http_header: 'X-Capture-Token' }, token: 'fixture-token')
    expect(requests.map { |r| r.fetch(:url) }).to eq([SchemaFixtures::URL, SchemaFixtures::URL])
    expect(requests.map { |r| r.fetch(:headers) }).to eq([{ accept: :json }, { accept: :json, 'X-Capture-Token' => 'fixture-token' }])
    expect(result['description']['resources'].keys).to eq(['authorized'])
    expect(JSON.generate(result)).not_to include('fixture-token')
  end

  it 'refuses missing or invalid token discovery before sending the token' do
    expect { fetch(token: 'fixture-token') }.to raise_error(HaveAPI::Schema::Error, /does not advertise/)
    expect(RestClient::Request).to have_received(:execute).once
    anonymous = envelope
    anonymous['response']['authentication'] = { 'token' => { 'http_header' => "X-Bad\r\nfixture-secret" } }
    allow(RestClient::Request).to receive(:execute).and_return(double(code: 200, to_s: JSON.generate(anonymous)))
    stub_const('HaveAPI::Client::Authentication::Token', Class.new)
    allow(described_class).to receive(:require).with('haveapi/client').and_return(true)
    allow(HaveAPI::Client::Authentication::Token).to receive(:new).and_raise(ArgumentError, 'fixture-secret')
    expect { fetch(token: 'fixture-token') }.to raise_error(HaveAPI::Schema::Error) do |error|
      expect(error.message).to include('invalid HaveAPI token HTTP header')
      expect(error.full_message).not_to include('fixture-secret', 'fixture-token')
    end
    expect(RestClient::Request).to have_received(:execute).twice
  end

  it 'validates versions, endpoints, profile and exclusive credentials before dispatch' do
    [
      { api_version: nil }, { url: 'https://schema.example.test/mount/' }, { profile: '' },
      { url: 'https://user:fixture-secret@schema.example.test/v7.0/' },
      { basic_user: 'user' }, { basic_password: 'secret' }, { basic_user: 'a:b', basic_password: 'secret' },
      { token: false }, { basic_user: false }, { basic_password: false },
      { token: '' }, { token: "secret\n" }, { token: 'secret', basic_user: 'user', basic_password: 'secret' }
    ].each do |options|
      expect { fetch(**options) }.to raise_error(HaveAPI::Schema::Error)
    end
    expect(RestClient::Request).not_to have_received(:execute)
  end

  it 'rejects redirects, transport errors and unsuccessful or incoherent envelopes without leaking bodies' do
    allow(RestClient::Request).to receive(:execute).and_raise(StandardError, 'fixture-password in raw HTTP error')
    expect { fetch }.to raise_error(HaveAPI::Schema::Error) { |error| expect(error.full_message).not_to include('fixture-password') }
    [double(code: 302, to_s: 'fixture-secret'), double(code: 200, to_s: 'fixture-secret'),
     double(code: 200, to_s: JSON.generate(envelope.merge('status' => false))),
     double(code: 200, to_s: JSON.generate(envelope.merge('version' => '3.0')))].each do |response|
      allow(RestClient::Request).to receive(:execute).and_return(response)
      expect { fetch }.to raise_error(HaveAPI::Schema::Error) { |error| expect(error.full_message).not_to include('fixture-secret') }
    end
    expect(RestClient::Request).to have_received(:execute).exactly(5).times
  end
end
