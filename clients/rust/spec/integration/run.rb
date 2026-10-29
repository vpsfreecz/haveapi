# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] = File.expand_path('../../Gemfile', __dir__)
require 'bundler/setup'
require 'fileutils'
require 'json'
require 'io/wait'
require 'open3'
require 'rbconfig'
require 'tempfile'
require 'tmpdir'
require_relative '../../lib/haveapi/rust_client'

module RustClientIntegration
  ROOT = File.expand_path('../..', __dir__)
  SERVER_GEMFILE = File.expand_path('../../servers/ruby/Gemfile', ROOT)
  SERVER_GEM_HOME = File.expand_path('../../.gems', ROOT)

  module_function

  def with_server(mount, documentation_examples: false)
    log = Tempfile.create('rust-haveapi-fixture-log')
    command = [
      'bundle', 'exec', RbConfig.ruby,
      File.join(__dir__, 'support/haveapi_server.rb'), '--mount', mount
    ]
    command << '--documentation-examples' if documentation_examples
    input, output, waiter = Bundler.with_unbundled_env do
      Open3.popen2(
        { 'BUNDLE_GEMFILE' => SERVER_GEMFILE, 'GEM_HOME' => SERVER_GEM_HOME, 'GEM_PATH' => nil },
        *command, err: log.path
      )
    end
    input.close
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    url = nil
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      raise "HaveAPI fixture exited before readiness; log #{log.path}" unless waiter.alive?
      next unless output.wait_readable(0.1)

      line = output.gets
      break if line.nil?
      next unless line.start_with?('HAVEAPI_TEST_SERVER_READY ')

      url = line.split.fetch(1)
      break
    end
    raise 'HaveAPI fixture readiness deadline exceeded' unless url

    yield "#{url}#{mount}"
  ensure
    if waiter&.alive?
      Process.kill('TERM', waiter.pid)
      unless waiter.join(10)
        Process.kill('KILL', waiter.pid)
        waiter.join
      end
    end
    output&.close
    if log
      log.close
      if $!.nil?
        File.unlink(log.path)
      else
        warn "HaveAPI fixture failure log: #{log.path}"
      end
    end
  end

  def write_crate(dir)
    FileUtils.mkdir_p(File.join(dir, 'src'))
    FileUtils.mkdir_p(File.join(dir, 'tests'))
    File.write(File.join(dir, 'src/lib.rs'), "mod generated;\npub use generated::*;\n")
    Dir[File.join(__dir__, 'rust/*.rs')].each do |source|
      FileUtils.cp(source, File.join(dir, 'tests', File.basename(source)))
    end
  end

  def run
    # Explicit opt-in keeps ordinary generator specs lightweight.
    abort 'Set HAVEAPI_RUST_INTEGRATION=1 to run server acceptance' unless ENV['HAVEAPI_RUST_INTEGRATION'] == '1'

    Dir.mktmpdir('haveapi-rust-integration-') do |dir|
      write_crate(dir)
      ['/', '/mounted/api/'].each do |mount|
        with_server(mount) do |url|
          snapshot = HaveAPI::RustClient::Snapshot.fetch(
            url: "#{url}v1.0/", api_version: '1.0', profile: 'local-rust-integration'
          )
          begin
            HaveAPI::RustClient::Snapshot.fetch(
              url: "#{url}v999.0/", api_version: '999.0', profile: 'unavailable-version'
            )
          rescue HaveAPI::RustClient::Error
            # Explicit unknown versions must fail rather than select default.
          else
            raise 'Unavailable API version unexpectedly selected a description'
          end
          config = {
            'crate_name' => 'haveapi-rust-fixture', 'crate_version' => '0.1.0',
            'license' => 'MIT', 'edition' => '2024', 'rust_version' => '1.95',
            'rustfmt_version' => IO.popen(%w[rustfmt --version], &:read).strip
          }
          generated = File.join(dir, 'src/generated')
          generator = HaveAPI::RustClient::Generator.new(schema: snapshot, config: config)
          manifest = generator.manifest_requirements.sub('[package]', "[package]\npublish = false")
          File.write(File.join(dir, 'Cargo.toml'), manifest)
          generator.generate(output: generated)
          generator.generate(output: generated, check: true)
          unless system('cargo', 'fmt', '--manifest-path', File.join(dir, 'Cargo.toml'), '--all', '--', '--check')
            raise "Generated fixture formatting failed at mount #{mount}"
          end

          if ENV['HAVEAPI_RUST_NAME_LINT'] == '1'
            lint_generated_names(dir)
          else
            # Fresh server per mount, shared generated request/response assertions
            # in both execution modes. Cargo's exit status is the acceptance gate.
            ok = system(
              { 'HAVEAPI_TEST_BASE_URL' => url },
              'cargo', 'test', '--manifest-path', File.join(dir, 'Cargo.toml'),
              '--all-features', '--', '--test-threads=1'
            )
            raise "Generated fixture acceptance failed at mount #{mount}" unless ok
          end
        end
      end
    end
  end

  def lint_generated_names(dir)
    msrv_cargo = ENV.fetch('HAVEAPI_RUST_MSRV_CARGO')
    msrv_rustc = ENV.fetch('HAVEAPI_RUST_MSRV_RUSTC')
    output, status = Open3.capture2(msrv_rustc, '--version')
    raise 'Rust name lint MSRV compiler must be 1.95' unless status.success? && output.start_with?('rustc 1.95.')
    if %w[RUSTC RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER].any? { |key| !ENV.fetch(key, '').empty? }
      raise 'Unset inherited compiler overrides before checking generated names'
    end

    manifest = File.join(dir, 'Cargo.toml')
    raise 'Unable to lock generated name fixture' unless system('cargo', 'generate-lockfile', '--manifest-path', manifest)

    [['cargo', {}], [msrv_cargo, { 'RUSTC' => msrv_rustc }]].each do |cargo, env|
      ok = system(env, cargo, 'rustc', '--locked', '--manifest-path', manifest, '--lib', '--all-features', '--', '-D', 'non_snake_case')
      raise 'Generated resource names fail the scoped naming lint' unless ok
    end
  end
end

RustClientIntegration.run if $0 == __FILE__
