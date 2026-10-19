# frozen_string_literal: true

# Load with --options /dev/null. api/.rspec would otherwise require spec_helper
# before the guards below and could reset an inherited database.
require 'open3'
require 'json'
require 'digest'
require 'tmpdir'
require 'timeout'

raise 'spec_helper was loaded before the database safety guard' if defined?(SpecDbSetup)
raise 'RACK_ENV must be test' unless ENV['RACK_ENV'] == 'test'
raise 'Only the core API is supported' unless ENV['VPSADMIN_PLUGINS'] == 'none'
raise 'Native isolated database startup must be enabled' unless ENV['VPSADMIN_TEST_DB_AUTO'] == '1'
raise 'Refusing an inherited DATABASE_URL' if ENV.has_key?('DATABASE_URL')

api_dir = File.realpath(Dir.pwd)
raise 'Run from the reference api directory' unless File.file?(File.join(api_dir, 'spec/spec_helper.rb'))
raise 'Refusing database.yml' if File.exist?(File.join(api_dir, 'config/database.yml'))

reference = File.realpath(File.join(api_dir, '..'))
expected = ENV.fetch('HAVEAPI_VPSADMIN_EXPECTED_REV')
revision, status = Open3.capture2('git', '-C', reference, 'rev-parse', 'HEAD')
raise 'vpsAdmin reference revision mismatch' unless status.success? && revision.strip == expected
raise 'Unexpected vpsAdmin baseline' unless expected == 'fb2f51222503a45f2e5a42af505f719e44279ed0'

project = File.realpath(ENV.fetch('HAVEAPI_PYTHON_PROJECT'))
python = File.expand_path(ENV.fetch('HAVEAPI_PYTHON_EXECUTABLE'))
raise 'Use the prepared Python environment' unless python == File.join(project, '.venv/bin/python') && File.executable?(python)
raise 'Missing Python lock' unless File.file?(File.join(project, 'uv.lock'))
raise 'Expected server version must be 0.29.12' unless ENV.fetch('HAVEAPI_EXPECTED_SERVER_VERSION') == '0.29.12'
raise 'Evidence directory is required' unless File.directory?(File.realpath(ENV.fetch('HAVEAPI_VPSADMIN_EVIDENCE_DIR')))

require File.join(api_dir, 'spec/spec_helper.rb')
require 'rackup/handler/webrick'
require 'webrick'

unless Gem.loaded_specs.fetch('haveapi').version.to_s == ENV.fetch('HAVEAPI_EXPECTED_SERVER_VERSION')
  raise 'Loaded HaveAPI version does not match the released baseline'
end

# SIGTERM unwinds ensure blocks and native DB at_exit ownership.
Signal.trap('TERM') { raise Interrupt, 'vpsAdmin bridge cancelled' }

module PythonVpsadminBridge
  PASSWORD = 'python-client-fixture-old-password'
  NEW_PASSWORD = 'python-client-fixture-new-password'

  def bridge_manifest(scenario, mode)
    user = SpecSeed.user.reload
    admin = SpecSeed.admin.reload
    [user, admin, SpecSeed.other_user.reload].each do |account|
      SpecSeed.set_password!(account, PASSWORD)
      account.update!(
        enable_basic_auth: true,
        enable_token_auth: true,
        enable_multi_factor_auth: false,
        enable_new_login_notification: false,
        password_reset: false,
        lockout: false
      )
    end
    UserTotpDevice.where(user:).destroy_all
    User.current = nil
    UserSession.current = nil

    own = 3.times.map do |i|
      hostname = "python-client-user-#{i}"
      Vps.find_by(hostname:) || create_vps!(user:, node: SpecSeed.node, hostname:)
    end
    other = Vps.find_by(hostname: 'python-client-other') || create_vps!(
      user: SpecSeed.other_user, node: SpecSeed.other_node, hostname: 'python-client-other'
    )
    interface = NetworkInterface.find_by(vps: own.first, name: 'eth0') || create_network_interface!(own.first, name: 'eth0')
    NetworkInterface.find_by(vps: other, name: 'eth0') || create_network_interface!(other, name: 'eth0')

    manifest = {
      scenario:, mode:, password: PASSWORD, new_password: NEW_PASSWORD,
      user: { id: user.id, login: user.login },
      admin: { id: admin.id, login: admin.login },
      own_vps_ids: own.map(&:id).sort,
      other_vps_id: other.id,
      own_interface_id: interface.id,
      os_template_id: SpecSeed.os_template.id
    }
    if %w[totp totp_reset].include?(scenario)
      user.update!(enable_multi_factor_auth: true)
      manifest[:totp_secret] = create_totp_device!(user:).secret
    end
    user.update!(password_reset: true) if %w[reset totp_reset].include?(scenario)
    if scenario == 'tokens'
      session = create_open_session!(user:, auth_type: 'token', valid_to: 1.minute.ago)
      manifest[:expired_token] = session.token.token
    end
    manifest
  end

  def with_bridge_server
    # Return the connection when a response body has finished, not before Rack
    # has produced it. HaveAPI currently returns finite JSON response bodies.
    rack_app = lambda do |env|
      ActiveRecord::Base.connection_pool.with_connection do
        status, headers, body = ApiAppHelper.app_instance.call(env)
        chunks = []
        begin
          body.each { |chunk| chunks << chunk }
        ensure
          body.close if body.respond_to?(:close)
        end
        [status, headers, chunks]
      end
    end
    listener = nil
    worker = Thread.new do
      Rackup::Handler::WEBrick.run(
        rack_app, Host: '127.0.0.1', Port: 0,
                  AccessLog: [], Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::FATAL)
      ) { |server| listener = server }
    end
    worker.report_on_exception = false
    begin
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
      until listener && listener.status == :Running
        raise 'WEBrick exited before readiness' unless worker.alive?
        raise 'WEBrick readiness timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.02
      end
      port = listener.listeners.fetch(0).addr[1]
      yield "http://127.0.0.1:#{port}/"
    ensure
      listener&.shutdown
      raise 'WEBrick did not stop' unless worker.join(10)

      worker.value
    end
  end

  def run_python_scenario(manifest)
    scenario = manifest.fetch(:scenario)
    mode = manifest.fetch(:mode)
    raise 'Unknown scenario' unless %w[reads tokens totp reset totp_reset].include?(scenario)
    raise 'Unknown client mode' unless %w[sync async].include?(mode)

    project = File.realpath(ENV.fetch('HAVEAPI_PYTHON_PROJECT'))
    python = File.expand_path(ENV.fetch('HAVEAPI_PYTHON_EXECUTABLE'))
    Dir.mktmpdir('haveapi-vpsadmin-manifest-') do |dir|
      path = File.join(dir, 'manifest.json')
      File.write(path, JSON.generate(manifest), mode: 'w', perm: 0o600)
      environment = ENV.to_h
      environment.keys.grep(/\A(?:BUNDLE_|BUNDLER_|RUBY|GEM_|PYTHONPATH\z|PYTHONHOME\z)/).each do |key|
        environment.delete(key)
      end
      environment.delete('DATABASE_URL')
      environment['HAVEAPI_VPSADMIN_MANIFEST'] = path
      output = File.join(dir, 'pytest.log')
      pid = nil
      child_status = nil
      begin
        File.open(output, 'w', 0o600) do |log|
          pid = Process.spawn(
            environment, python, '-m', 'pytest',
            "tests/integration/test_vpsadmin_live.py::test_#{manifest.fetch(:scenario)}",
            '-q', '--tb=short', '--no-header', '-o', 'addopts=',
            chdir: project, out: log, err: log, unsetenv_others: true
          )
          Timeout.timeout(180) { _pid, child_status = Process.wait2(pid) }
          pid = nil
        end
        # The raw child output remains private and is removed with its manifest.
        # Retain only bounded stack locations/types, never messages or values.
        warn "Python #{scenario}/#{mode}: exit #{child_status.exitstatus}"
        unless child_status.success?
          evidence = retain_python_failure(output, manifest.fetch(:scenario), manifest.fetch(:mode))
          warn "Safe Python failure traceback: #{evidence}"
        end
        expect(child_status.success?).to be(true), 'Python vpsAdmin scenario failed; inspect the named scenario without exposing its private manifest'
      ensure
        if pid
          begin
            Process.kill('TERM', pid)
            Timeout.timeout(5) { Process.wait(pid) }
          rescue Timeout::Error
            Process.kill('KILL', pid)
            Process.wait(pid)
          rescue Errno::ESRCH, Errno::ECHILD
            nil
          end
        end
      end
    end
  end

  def retain_python_failure(output, scenario, mode)
    raise 'Unknown scenario' unless %w[reads tokens totp reset totp_reset].include?(scenario)
    raise 'Unknown client mode' unless %w[sync async].include?(mode)

    project = File.realpath(ENV.fetch('HAVEAPI_PYTHON_PROJECT'))
    # Only existing project sources can contribute locations. Ignore function
    # names: remote exception text could contain forged traceback-looking lines.
    files = Dir.glob(File.join(project, 'src/haveapi_client/**/*.py')) +
            %w[test_vpsadmin_live.py vpsadmin_support.py].map do |name|
              File.join(project, 'tests/integration', name)
            end
    line_counts = files.to_h { |file| [file, File.foreach(file).count] }
    types = %w[AssertionError Failed KeyError AttributeError TypeError ValueError
               AuthenticationError ActionError ProtocolError ValidationError
               TransportError NotConnectedError StaleDescriptionError TimeoutError]
    lines = File.readlines(output).filter_map do |line|
      if (frame = line.match(/\A([^:\r\n]+\.py):(\d+): in [\w<>]+\s*\z/))
        file = File.expand_path(frame[1], project)
        count = line_counts[file]
        next unless count && frame[2].bytesize <= count.to_s.length

        number = Integer(frame[2], 10)
        "#{file.delete_prefix("#{project}/")}:#{number}" if number.between?(1, count)
      elsif (error = line.match(/\AE\s+([A-Za-z_]\w*(?:Error|Exception)|Failed):/))
        type = types.include?(error[1]) ? error[1] : 'Exception'
        "#{type}: <message redacted>"
      end
    end
    lines = ['No Python stack locations or exception types were emitted'] if lines.empty?
    path = File.join(
      File.realpath(ENV.fetch('HAVEAPI_VPSADMIN_EVIDENCE_DIR')),
      "vpsadmin-#{scenario}-#{mode}-failure.log"
    )
    node = "test_vpsadmin_live.py::test_#{scenario} [#{mode}]"
    text = ([node] + lines.last(80)).join("\n")
    File.write(path, "#{text}\n", mode: 'w', perm: 0o600)
    File.chmod(0o600, path)
    path
  end
end

RSpec.describe PythonVpsadminBridge, :no_transaction do
  include CoreResourceSpecHelpers
  include VpsChainSpecHelpers
  include AuthOperationHelpers
  include described_class

  before do
    # Only network PTR resolution and external notification dispatch are replaced.
    resolver = instance_double(Resolv, getname: 'localhost')
    allow(Resolv).to receive(:new).and_return(resolver)
    allow(TransactionChains::User::PasswordChanged).to receive(:fire)
  end

  before(:context) do
    root = File.realpath(File.join(ENV.fetch('HAVEAPI_PYTHON_PROJECT'), '../..'))
    client_revision, = Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD')
    evidence = {
      vpsadmin_revision: ENV.fetch('HAVEAPI_VPSADMIN_EXPECTED_REV'),
      python_client_revision: client_revision.strip,
      haveapi_version: Gem.loaded_specs.fetch('haveapi').version.to_s,
      ruby_version: RUBY_VERSION,
      bundler_version: Bundler::VERSION,
      api_lock_sha256: Digest::SHA256.file(File.join(Dir.pwd, 'Gemfile.lock')).hexdigest,
      python_lock_sha256: Digest::SHA256.file(File.join(ENV.fetch('HAVEAPI_PYTHON_PROJECT'), 'uv.lock')).hexdigest,
      side_effects_replaced: %w[PTR_lookup PasswordChanged_notification],
      database_owner: 'native SpecDbSetup auto-start helper; stop/prune at exit'
    }
    python_version, = Open3.capture2(ENV.fetch('HAVEAPI_PYTHON_EXECUTABLE'), '--version')
    evidence[:python_version] = python_version.strip
    warn "HAVEAPI_VPSADMIN_EVIDENCE #{JSON.generate(evidence)}"
  end

  %w[reads tokens totp reset totp_reset].each do |scenario|
    %w[sync async].each do |mode|
      it "supports #{scenario} with the #{mode} client" do
        manifest = bridge_manifest(scenario, mode)
        with_bridge_server do |url|
          manifest[:base_url] = url
          run_python_scenario(manifest)
        end
        user = SpecSeed.user.reload
        expect(user.password_reset).to be(false) if %w[reset totp_reset].include?(scenario)
        if %w[tokens totp reset totp_reset].include?(scenario)
          expect(UserSession.where(user:, auth_type: 'token').count).to be_positive
        end
      end
    end
  end
end
