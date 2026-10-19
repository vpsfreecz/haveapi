require 'bundler/setup'
require 'haveapi/rust_client'
require 'open3'
require 'tmpdir'

RSpec.configure do |config|
  config.order = :random
end

module RustGeneratorFixtures
  def generator_config
    stdout, _stderr, status = Open3.capture3(ENV.fetch('RUSTFMT', 'rustfmt'), '--version')
    raise 'Unable to determine fixture rustfmt version' unless status.success? && !stdout.strip.empty?

    {
      'crate_name' => 'fixture-client', 'crate_version' => '0.1.0', 'license' => 'MIT',
      'edition' => '2024', 'rust_version' => '1.95', 'rustfmt_version' => stdout.strip
    }
  end

  def io(parameters = {}, namespace: 'widget', layout: 'object', **fields)
    parameters = parameters.merge(fields.transform_keys(&:to_s))
    { 'parameters' => parameters, 'namespace' => namespace, 'layout' => layout }
  end

  def parameter(type = 'String', **options)
    { 'type' => type, 'required' => false, 'nullable' => false, 'protected' => false }.merge(options.transform_keys(&:to_s))
  end

  def action(path: '/v1.0/widgets/{widget_id}', method: 'PUT', input: nil, output: nil)
    {
      'path' => path, 'method' => method, 'aliases' => [], 'auth' => true,
      'input' => input || io('name' => parameter('String', nullable: true)),
      'output' => output || io('id' => parameter('Integer'), 'name' => parameter),
      'meta' => { 'global' => nil, 'object' => nil }
    }
  end

  def snapshot(actions: nil)
    HaveAPI::RustClient::Snapshot.from_description(
      api_version: '1.0', protocol_version: '2.0', source_url: 'https://example.test/v1.0/',
      profile: 'fixture', description: {
        'help' => '/v1.0/', 'meta' => { 'namespace' => '_meta' }, 'authentication' => { 'basic' => {} },
        'resources' => { 'widget' => { 'actions' => actions || { 'update' => action }, 'resources' => {} } }
      }
    )
  end
end
