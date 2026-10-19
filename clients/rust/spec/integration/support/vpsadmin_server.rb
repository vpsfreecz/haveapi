# frozen_string_literal: true

require 'optparse'
require 'tmpdir'
require_relative 'serve'
require_relative 'vpsadmin_database'

options = {}
OptionParser.new do |opts|
  opts.on('--source-root PATH', 'Explicit disposable fixture source checkout') { |v| options[:source_root] = v }
end.parse!

abort '--source-root is required' unless options[:source_root]
abort 'Refusing inherited DATABASE_URL' if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?

root = File.realpath(options.fetch(:source_root))
abort 'Missing vpsAdmin fixture support' unless File.file?(File.join(root, 'api/spec/spec_helper.rb'))

# Do not let an API checkout configuration silently select another database.
# The helper below receives only the URL of the instance created here.
ENV['RACK_ENV'] = 'test'
ENV['VPSADMIN_PLUGINS'] = 'all'
ENV['VPSADMIN_TEST_DB_AUTO'] = '0'
require File.join(root, 'tools/test_db')

state_dir = RustClientFixtures.database_state_dir
File.chmod(0o700, state_dir)
db = VpsAdmin::TestDb::Instance.new(
  state_dir: state_dir, port: VpsAdmin::TestDb.free_port,
  database: 'rust_client_fixture'
)

begin
  db.start
  ENV['DATABASE_URL'] = db.url
  Dir.chdir(File.join(root, 'api')) do
    $:.unshift(File.join(root, 'api/spec'))
    require File.join(root, 'api/spec/spec_helper')

    # The canonical spec helper defines before(:suite), but this is a server,
    # not an RSpec run. Invoke the same public bootstrap helpers explicitly.
    SpecSeed.seed_language_if_needed!
    SpecDbSetup.seed_minimal_sysconfig!
    SpecDbSetup.seed_minimal_cluster_resources!
    app = ApiAppHelper.app_instance
    SpecPlugins.migrate_enabled_plugins!
    SpecSeed.bootstrap!
    TransactionKeyHelpers.install_encrypted_transaction_key!
    VpsAdmin::API::TransactionSigner.unlock(TransactionKeyHelpers::TEST_PASSPHRASE)

    helper = Object.new.extend(CoreResourceSpecHelpers, VpsStandaloneChainSpecHelpers)
    vps = helper.create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'rust-fixture-vps')
    zone = DnsZone.create!(
      name: 'rust-client.example.test.', user: SpecSeed.user,
      zone_role: :forward_role, zone_source: :internal_source,
      enabled: true, label: 'Rust client fixture', default_ttl: 3600,
      email: 'dns@example.test'
    )
    record = DnsRecord.create!(
      dns_zone: zone, name: 'www', record_type: 'A',
      content: '192.0.2.10', ttl: 120, enabled: true
    )

    # Token login notifications need a recent node status for mail dispatch.
    helper.ensure_available_node_status!(SpecSeed.node)

    RustClientFixtures.serve(app, metadata: {
      api_version: '7.0', vps_id: vps.id, dns_record_id: record.id,
      user_id: SpecSeed.user.id, setting_namespace: 'ui',
      setting_key: 'rust_client_fixture.wire_contract'
    })
  end
ensure
  # Stop/prune only the explicit instance created above. Never select the
  # repository's manual/default test database or any development session.
  begin
    ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base)
  ensure
    db.prune
  end
end
