# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'haveapi/cli'

RSpec.describe HaveAPI::CLI::Cli do
  around do |example|
    old_umask = File.umask(0o022)

    example.run
  ensure
    File.umask(old_umask) if old_umask
  end

  before do
    allow(Dir).to receive(:home).and_return(home)
  end

  after do
    FileUtils.rm_rf(home)
  end

  let(:home) { Dir.mktmpdir('haveapi-home-') }
  let(:config_path) { File.join(home, '.haveapi-client.yml') }
  let(:secret_token) { 'vuln75-secret-token' }
  let(:config) do
    {
      servers: [
        {
          url: 'https://api.example',
          auth: {
            token: {
              token: secret_token,
              valid_to: 1_800_000_000
            }
          },
          last_auth: :token
        }
      ]
    }
  end

  def cli_with_config(config)
    described_class.allocate.tap do |cli|
      cli.instance_variable_set(:@config, config)
    end
  end

  it 'creates saved credential config files with owner-only permissions' do
    cli_with_config(config).send(:write_config)

    expect(File.read(config_path)).to include(secret_token)
    expect(File.stat(config_path).mode & 0o777).to eq(0o600)
  end

  it 'narrows existing saved credential config files before rewriting them' do
    File.write(config_path, 'previous config')
    File.chmod(0o644, config_path)

    cli_with_config(config).send(:write_config)

    expect(File.read(config_path)).to include(secret_token)
    expect(File.stat(config_path).mode & 0o777).to eq(0o600)
  end
end
