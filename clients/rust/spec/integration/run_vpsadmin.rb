# frozen_string_literal: true

require 'io/wait'
require 'json'
require 'open3'
require 'optparse'
require 'tmpdir'
require 'uri'

module RustClientVpsadminIntegration
  module_function

  def fixture_url!(metadata)
    url = URI.parse(metadata.fetch('base_url'))
    unless url.scheme == 'http' && url.host == '127.0.0.1' && url.port > 0 &&
           url.userinfo.nil? && url.query.nil? && url.fragment.nil? && url.path.empty?
      raise 'Fixture readiness contained an invalid loopback URL'
    end

    %w[vps_id dns_record_id user_id].each do |name|
      value = metadata.fetch(name)
      raise "Fixture readiness has invalid #{name}" unless value.is_a?(Integer) && value > 0
    end
    raise 'Fixture API version differs from 7.0' unless metadata.fetch('api_version') == '7.0'

    url.to_s
  rescue KeyError, URI::InvalidURIError, JSON::ParserError
    raise 'Fixture readiness was malformed'
  end

  def readiness(output, waiter)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      raise 'vpsAdmin fixture exited before readiness; inspect private fixture.log' unless waiter.alive?
      next unless output.wait_readable(0.1)

      line = output.gets
      raise 'vpsAdmin fixture closed stdout before readiness; inspect private fixture.log' unless line
      next unless line.start_with?('VPSADMIN_FIXTURE_READY ')

      metadata = JSON.parse(line.delete_prefix('VPSADMIN_FIXTURE_READY '))
      fixture_url!(metadata)
      return metadata
    end
    raise 'vpsAdmin fixture readiness deadline exceeded; inspect private fixture.log'
  end

  def stop_fixture(waiter)
    return unless waiter&.alive?

    Process.kill('TERM', -waiter.pid)
    return if waiter.join(15)

    Process.kill('KILL', -waiter.pid)
    waiter.join
  rescue Errno::ESRCH
    waiter&.join
  end

  def run(argv)
    options = {}
    OptionParser.new do |opts|
      opts.on('--source-root PATH', 'vpsAdmin fixture source checkout') { |v| options[:source_root] = v }
      opts.on('--client-root PATH', 'Generated client repository') { |v| options[:client_root] = v }
      opts.on('--artifacts PATH', 'Parent directory for private logs') { |v| options[:artifacts] = v }
    end.parse!(argv)
    abort 'Set VPSADMIN_REAL_INTEGRATION=1 to run disposable server acceptance' unless ENV['VPSADMIN_REAL_INTEGRATION'] == '1'
    abort 'Refusing inherited DATABASE_URL' if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?
    abort '--source-root, --client-root and --artifacts are required' unless options.values_at(
      :source_root, :client_root, :artifacts
    ).all?

    source = File.realpath(options.fetch(:source_root))
    client = File.realpath(options.fetch(:client_root))
    evidence = Dir.mktmpdir('vpsadmin-client-acceptance-', File.realpath(options.fetch(:artifacts)))
    File.chmod(0o700, evidence)
    fixture_log = File.join(evidence, 'fixture.log')
    command = [
      'nix', 'develop', '.#api', '--command', 'bundle', 'exec', 'ruby',
      File.join(__dir__, 'support/vpsadmin_server.rb'), '--source-root', source
    ]
    input, output, waiter = Open3.popen2(
      { 'VPSADMIN_PLUGINS' => 'all' }, *command,
      chdir: source, pgroup: true, err: fixture_log
    )
    input.close
    metadata = readiness(output, waiter)
    # Drain remaining stdout so a verbose source server cannot block. Store it
    # privately: API diagnostics can contain request or response data.
    drain = Thread.new do
      File.open(File.join(evidence, 'fixture.stdout.log'), 'wb') { |file| IO.copy_stream(output, file) }
    end
    env = {
      'VPSADMIN_REAL_INTEGRATION' => '1',
      'VPSADMIN_TEST_BASE_URL' => fixture_url!(metadata),
      'VPSADMIN_FIXTURE_JSON' => JSON.generate(metadata)
    }
    ok = system(
      env, 'nix', 'develop', '--command', 'cargo', 'test', '--locked',
      '--all-features', '--test', 'real_vpsadmin', '--', '--ignored', '--test-threads=1',
      chdir: client
    )
    raise "Actual vpsAdmin generated-client acceptance failed; evidence #{evidence}" unless ok

    receipt = {
      'result' => 'passed', 'api_version' => '7.0',
      'fixture_source' => source, 'client_source' => client
    }
    File.write(File.join(evidence, 'result.json'), JSON.pretty_generate(receipt))
    warn "Actual vpsAdmin generated-client acceptance passed; evidence #{evidence}"
  ensure
    stop_fixture(waiter)
    drain&.join
    output&.close
  end
end

RustClientVpsadminIntegration.run(ARGV) if $0 == __FILE__
