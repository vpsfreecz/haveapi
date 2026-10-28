$:.unshift(File.expand_path('../../../ruby/lib', __dir__))
require_relative '../spec_helper'
require_relative '../typescript/fixtures'
require_relative '../../lib/haveapi/typescript_client/documentation'

module TypeScriptDocumentationFixtures
  include TypeScriptEmitterFixtures

  Context = Struct.new(:version, :base_url, :version_url, :description, :resource_path, :action_name, :action, :sample, :detail)

  def documentation_snapshot(mount: '/api/')
    schema = emitter_schema
    rewrite = lambda do |value|
      case value
      when Hash then value.to_h { |key, item| [key, rewrite.call(item)] }
      when Array then value.map { |item| rewrite.call(item) }
      when String then value.start_with?('/api/') ? value.sub('/api/', mount) : value
      else value
      end
    end
    schema = rewrite.call(schema)
    schema['mount_path'] = mount
    schema['source_url'] = "https://schema.invalid#{mount}v1.0/"
    schema['description']['authentication'] = { 'basic' => {}, 'token' => { 'http_header' => 'X-Widget-Token' } }
    walk = lambda do |resources|
      resources.each_value do |resource|
        resource['actions'].each_value { |item| item['auth'] = false }
        walk.call(resource['resources'])
      end
    end
    walk.call(schema['description']['resources'])
    schema
  end

  def documentation_context(schema = documentation_snapshot, action_name: 'update', resource_path: ['widget'], base: 'https://api.example.test', detail: :thorough)
    description = Marshal.load(Marshal.dump(schema.fetch('description')))
    resource = description
    resource_path.each { |name| resource = resource.fetch('resources').fetch(name) }
    action = resource.fetch('actions').fetch(action_name)
    sample = case action_name
             when 'update'
               { status: true, path_params: ['a/b'], request: { 'name' => '', 'enabled' => false, 'count' => 0, 'cleared' => nil, 'wire-name' => 'mapped',
                                                                'custom' => { 'array' => [false, 0, nil], '__proto__' => { 'kept' => true } } },
                 response: { 'name' => nil, 'custom' => { 'opaque' => true }, 'owner' => { 'key' => 2, 'title' => 'Owner' }, 'wire-name' => 'raw' } }
             when 'index'
               { status: true, path_params: [], request: { 'limit' => 0, 'custom' => nil }, response: [{ 'name' => nil }] }
             when 'show'
               { status: true, path_params: [1, 'x/y'], request: {}, response: { 'id' => 2 } }
             else
               { status: true, path_params: [], request: {}, response: {} }
             end
    mount = schema.fetch('mount_path')
    Context.new(version: schema.fetch('api_version'), base_url: "#{base}#{mount}", version_url: "#{base}#{mount}v1.0/",
                description:, resource_path:, action_name:, action:, sample:, detail:)
  end

  def documentation_adapter(schema = documentation_snapshot)
    HaveAPI::TypeScriptClient::Documentation.from_snapshot(snapshot: schema, package_name: 'widget-client', package_version: '1.2.3')
  end
end
