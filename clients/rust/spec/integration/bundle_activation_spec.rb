# frozen_string_literal: true

require 'rspec'
require_relative 'run'

RSpec.describe RustClientIntegration do
  it 'activates the component path dependency when loaded by plain Ruby' do
    runner = File.expand_path('run.rb', __dir__)
    component_gems = File.join(described_class::ROOT, '.gems')
    env = {
      'GEM_HOME' => component_gems,
      'GEM_PATH' => [Gem.default_dir, component_gems].join(File::PATH_SEPARATOR),
      'BUNDLE_GEMFILE' => nil, 'RUBYOPT' => nil
    }
    code = <<~RUBY
      load ARGV.fetch(0)
      require 'haveapi/client'
      puts Gem.loaded_specs.fetch('haveapi-client').full_gem_path
    RUBY
    stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(env, RbConfig.ruby, '-e', code, runner)
    end

    expect(status.success?).to be(true), stderr
    expect(stdout.strip).to eq(File.expand_path('../ruby', described_class::ROOT))
  end

  it 'loads the separate server bundle and retains Ruby default gems' do
    # Probe bundle loading only: no socket, HaveAPI instance or Cargo process.
    probe = <<~RUBY
      require 'haveapi'
      require 'webrick'
      abort 'wrong fixture Gemfile' unless Bundler.default_gemfile.to_s == #{described_class::SERVER_GEMFILE.inspect}
      abort 'Ruby defaults hidden' unless Gem.path.include?(Gem.default_dir)
      puts 'HAVEAPI_TEST_SERVER_READY http://127.0.0.1:12345'
      $stdout.flush
      sleep 5
    RUBY
    allow(Open3).to receive(:popen2).and_wrap_original do |popen, env, *_command, **options|
      expect(env.fetch('BUNDLE_GEMFILE')).to eq(described_class::SERVER_GEMFILE)
      expect(env.fetch('GEM_HOME')).to eq(described_class::SERVER_GEM_HOME)
      expect(env.fetch('GEM_PATH')).to be_nil
      popen.call(env, 'bundle', 'exec', RbConfig.ruby, '-e', probe, **options)
    end

    expect { |block| described_class.with_server('/', &block) }
      .to yield_with_args('http://127.0.0.1:12345/')
  end
end
