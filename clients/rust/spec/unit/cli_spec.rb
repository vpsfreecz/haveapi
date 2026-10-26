require_relative '../spec_helper'
require 'haveapi/rust_client/cli'
require 'stringio'

RSpec.describe HaveAPI::RustClient::Cli do
  include RustGeneratorFixtures

  it 'requires an explicit version before any fetch or output write' do
    error = StringIO.new
    allow(HaveAPI::Schema::Capture).to receive(:fetch)
    status = described_class.run(['fetch', 'https://example.test/v1.0/', '--profile', 'public', '--output', '/unused'], err: error)
    expect(status).to eq(1)
    expect(HaveAPI::Schema::Capture).not_to have_received(:fetch)
    expect(error.string).to include('explicit numeric API version')
  end

  it 'delegates fetch arguments and status to the common command' do
    args = ['https://example.test/v1.0/', '--api-version', '1.0', '--profile', 'public', '--output', 'schema.json']
    out = StringIO.new
    err = StringIO.new
    allow(HaveAPI::Schema::FetchCommand).to receive(:run).and_return(1)
    expect(described_class.run(['fetch', *args], out:, err:)).to eq(1)
    expect(HaveAPI::Schema::FetchCommand).to have_received(:run).with(args, out:, err:, command_name: 'haveapi-rust-client')
  end

  it 'rejects a snapshot version mismatch before opening config or creating output' do
    Dir.mktmpdir('haveapi-rust-cli-') do |dir|
      schema = File.join(dir, 'schema.json')
      File.write(schema, HaveAPI::RustClient::Snapshot.canonical(snapshot))
      error = StringIO.new
      status = described_class.run([
                                     'generate', '--schema', schema, '--api-version', '2.0', '--config', 'not-read.toml', '--output', File.join(dir, 'out')
                                   ], err: error)
      expect(status).to eq(1)
      expect(error.string).to include('differs from snapshot')
      expect(File.exist?(File.join(dir, 'out'))).to be(false)
    end
  end
end
