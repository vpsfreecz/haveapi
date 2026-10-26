$:.unshift(File.expand_path('../../ruby/lib', __dir__))
require_relative '../lib/haveapi/typescript_client'
require_relative '../lib/haveapi/typescript_client/cli'
require 'tmpdir'
require 'stringio'

RSpec.configure { |config| config.order = :random }

module TypeScriptFixtures
  def parameter(kind = 'String', **flags)
    { 'type' => kind, 'required' => false, 'nullable' => false, 'protected' => false }.merge(flags.transform_keys(&:to_s))
  end

  def io(parameters = {}, namespace: 'widget', layout: 'object', **fields)
    { 'layout' => layout, 'namespace' => namespace, 'parameters' => parameters.merge(fields.transform_keys(&:to_s)) }
  end

  def action(path: '/api/v1.0/widgets/{widget_id}', method: 'PUT')
    {
      'path' => path, 'method' => method, 'auth' => true, 'blocking' => false, 'aliases' => [],
      'input' => io('name' => parameter(nullable: true)),
      'output' => io('id' => parameter('Integer')), 'meta' => { 'global' => nil, 'object' => nil }
    }
  end

  def snapshot
    HaveAPI::TypeScriptClient::Snapshot.from_description(
      api_version: '1.0', protocol_version: '2.0', source_url: 'https://schema.invalid/api/v1.0/',
      mount_path: '/api/', profile: 'fixture', description: {
        'help' => '/api/v1.0/', 'meta' => { 'namespace' => '_meta' }, 'authentication' => {},
        'resources' => { 'widget' => { 'actions' => { 'update' => action }, 'resources' => {} } }
      }
    )
  end

  def fixture_action(schema)
    schema.fetch('description').fetch('resources').fetch('widget').fetch('actions').fetch('update')
  end
end
