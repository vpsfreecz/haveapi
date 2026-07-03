# frozen_string_literal: true

require 'spec_helper'
require 'haveapi/cli'

RSpec.describe HaveAPI::CLI::Cli do
  def with_argv(*argv)
    old_argv = ARGV.dup
    ARGV.replace(argv)
    yield
  ensure
    ARGV.replace(old_argv)
  end

  def fake_cli_api(language)
    Class.new do
      attr_accessor :language

      def initialize(language)
        @language = language
      end

      def describe_api(_version = nil)
        { authentication: { fake: {} } }
      end
    end.new(language)
  end

  def parsed_cli_api(*argv)
    cli = described_class.allocate
    cli.instance_variable_set(:@config, {})

    allow(cli).to receive(:connect_api) do
      cli.instance_variable_set(
        :@api,
        fake_cli_api(cli.instance_variable_get(:@opts)&.[](:language))
      )
    end

    with_argv(*argv) { cli.send(:options) }
    cli.instance_variable_get(:@api)
  end

  it 'applies --language to no-auth CLI connections' do
    expect(parsed_cli_api('--language', 'cs', 'test', 'fail').language).to eq('cs')
  end

  it 'keeps --language when auth is parsed before language' do
    old_auth_methods = (described_class.auth_methods || {}).dup
    fake_auth = Class.new do
      def initialize(*); end
      def options(_opts); end
    end

    described_class.auth_methods = old_auth_methods.merge(fake: fake_auth)

    expect(
      parsed_cli_api('--auth', 'fake', '--language', 'cs', 'test', 'fail').language
    ).to eq('cs')
  ensure
    described_class.auth_methods = old_auth_methods
  end
end
