require_relative '../spec_helper'

RSpec.describe HaveAPI::RustClient::Snapshot do
  include RustGeneratorFixtures

  it 'delegates mounted acquisition without changing the common capture contract' do
    options = { url: 'https://example.test/mounted/v1.0/', api_version: '1.0', profile: 'fixture', token: 'test-only' }
    expected = snapshot
    allow(HaveAPI::Schema::Capture).to receive(:fetch).and_return(expected)
    expect(described_class.fetch(**options)).to equal(expected)
    expect(HaveAPI::Schema::Capture).to have_received(:fetch).with(**options)
  end

  it 'preserves native generator errors at the shared acquisition boundary' do
    allow(HaveAPI::Schema::Capture).to receive(:fetch).and_raise(HaveAPI::Schema::Error, 'capture failed')
    expect { described_class.fetch(url: 'https://example.test/v1.0/', api_version: '1.0', profile: 'fixture') }
      .to raise_error(HaveAPI::RustClient::Error, 'capture failed')
  end

  it 'preserves canonical bytes and helpers through the compatibility facade' do
    schema = snapshot
    expect(described_class.canonical(schema)).to eq(HaveAPI::Schema::Snapshot.canonical(schema))
    expect(described_class.sha256(schema)).to eq(HaveAPI::Schema::Snapshot.sha256(schema))
    expect(described_class.safe_segments?('/mounted/v1.0/')).to be(true)
    expect { described_class.validate(schema.merge('api_version' => '2.0')) }.to raise_error(HaveAPI::RustClient::Error)
  end

  it 'rejects credential-bearing nested endpoints under the stronger common validation' do
    description = snapshot.fetch('description')
    description['authentication']['oauth2'] = { 'token_url' => 'https://user:secret@example.test/token' }
    expect do
      described_class.from_description(
        description:, api_version: '1.0', protocol_version: '2.0',
        source_url: 'https://example.test/v1.0/', profile: 'fixture'
      )
    end.to raise_error(HaveAPI::RustClient::Error, /unsafe machine endpoint/)
  end
end
