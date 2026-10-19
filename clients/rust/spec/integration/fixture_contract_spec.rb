# frozen_string_literal: true

require 'rspec'
require 'fileutils'
require_relative 'run_vpsadmin'
require_relative 'support/vpsadmin_database'

RSpec.describe RustClientVpsadminIntegration do
  let(:metadata) do
    {
      'base_url' => 'http://127.0.0.1:12345', 'api_version' => '7.0',
      'vps_id' => 1, 'dns_record_id' => 2, 'user_id' => 3
    }
  end

  it 'accepts the source launcher loopback URL and integer fixture IDs' do
    expect(described_class.fixture_url!(metadata)).to eq('http://127.0.0.1:12345')
  end

  {
    'a production origin' => 'https://api.vpsfree.cz',
    'a DNS hostname' => 'http://localhost:12345',
    'a non-loopback address' => 'http://192.0.2.1:12345',
    'a different protocol' => 'ftp://127.0.0.1:12345',
    'a credential-bearing URL' => 'http://fixture:unused@127.0.0.1:12345',
    'a URL with a path' => 'http://127.0.0.1:12345/v7.0/',
    'a URL with a query' => 'http://127.0.0.1:12345?fixture=1',
    'a URL with a fragment' => 'http://127.0.0.1:12345#fixture'
  }.each do |description, url|
    it "rejects #{description} before client execution" do
      expect { described_class.fixture_url!(metadata.merge('base_url' => url)) }.to raise_error(RuntimeError)
    end
  end

  %w[vps_id dns_record_id user_id].each do |field|
    it "rejects missing or invalid #{field}" do
      [nil, 0, -1, '1', false].each do |value|
        expect { described_class.fixture_url!(metadata.merge(field => value)) }.to raise_error(RuntimeError)
      end
      expect { described_class.fixture_url!(metadata.except(field)) }.to raise_error(RuntimeError)
    end
  end

  it 'rejects a fixture with a different API version' do
    expect { described_class.fixture_url!(metadata.merge('api_version' => '1.0')) }.to raise_error(RuntimeError)
  end

  it 'rejects a readiness record without its URL' do
    expect { described_class.fixture_url!(metadata.except('base_url')) }.to raise_error(RuntimeError)
  end

  it 'reports stdout closing before readiness as an early failure' do
    output, writer = IO.pipe
    writer.close
    waiter = instance_double(Thread, alive?: true)

    expect { described_class.readiness(output, waiter) }
      .to raise_error(RuntimeError, /closed stdout before readiness/)
  ensure
    output&.close
    writer&.close
  end

  it 'uses unique private database directories within the Unix socket path limit' do
    allow(Dir).to receive(:tmpdir).and_return("/artifacts/#{'long-' * 40}")
    paths = Array.new(2) { RustClientFixtures.database_state_dir }

    expect(paths.uniq.length).to eq(2)
    paths.each do |path|
      expect(File.stat(path).mode & 0o777).to eq(0o700)
      expect(File.join(path, 'mysql.sock').bytesize).to be <= 107
    end
  ensure
    paths&.each { |path| FileUtils.remove_entry(path) }
  end
end
