require_relative '../spec_helper'
require 'haveapi/rust_client/cli'
require 'stringio'

RSpec.describe HaveAPI::RustClient::Cli do
  include RustGeneratorFixtures

  it 'requires an explicit version before any fetch or output write' do
    error = StringIO.new
    allow(HaveAPI::RustClient::Snapshot).to receive(:fetch)
    status = described_class.run(['fetch', 'https://example.test/v1.0/', '--output', '/unused'], err: error)
    expect(status).to eq(1)
    expect(HaveAPI::RustClient::Snapshot).not_to have_received(:fetch)
    expect(error.string).to include('explicit numeric API version')
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
