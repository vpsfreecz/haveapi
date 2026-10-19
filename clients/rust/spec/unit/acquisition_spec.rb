require_relative '../spec_helper'

RSpec.describe HaveAPI::RustClient::Snapshot do
  include RustGeneratorFixtures

  it 'uses the existing metadata client with an explicit version and no redirects' do
    require 'haveapi/client'
    communicator = instance_double(HaveAPI::Client::Communicator)
    communicator.instance_variable_set(:@proto_version, '2.0')
    description = snapshot.fetch('description')
    description['help'] = '/mounted/v1.0/'
    description.fetch('resources').fetch('widget').fetch('actions').each_value do |item|
      item['path'] = "/mounted#{item.fetch('path')}"
    end
    allow(HaveAPI::Client::Communicator).to receive(:new).with('https://example.test/mounted/').and_return(communicator)
    allow(communicator).to receive(:describe_api).with('1.0').and_return(description)
    allow(RestClient::Resource).to receive(:new).and_call_original
    result = described_class.fetch(
      url: 'https://example.test/mounted/v1.0/', api_version: '1.0', profile: 'fixture'
    )
    expect(communicator).to have_received(:describe_api).with('1.0')
    expect(RestClient::Resource).to have_received(:new).with(
      'https://example.test/mounted/', max_redirects: 0, open_timeout: 10, read_timeout: 30
    )
    expect(result.fetch('mount_path')).to eq('/mounted/')
  end

  it 'rejects credential-bearing discovered URLs before a snapshot can be written' do
    description = snapshot.fetch('description')
    description['authentication']['oauth2'] = { 'token_url' => 'https://user:secret@example.test/token' }
    expect do
      described_class.from_description(
        description:, api_version: '1.0', protocol_version: '2.0',
        source_url: 'https://example.test/v1.0/', profile: 'fixture'
      )
    end.to raise_error(HaveAPI::RustClient::Error, /credentials/)
  end
end
