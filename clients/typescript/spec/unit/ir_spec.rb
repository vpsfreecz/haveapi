require_relative '../spec_helper'

RSpec.describe HaveAPI::TypeScriptClient::IR do
  include TypeScriptFixtures

  it 'shares deeply frozen action records and preserves nested boundaries and routes' do
    schema = snapshot
    parent = schema['description']['resources']['widget']
    parent['resources']['part'] = { 'resources' => {}, 'actions' => {
      'show' => action(path: '/api/v1.0/widgets/{widget_id}/parts/{part_id}', method: 'GET')
    } }
    parent['actions']['update']['aliases'] = ['change']
    model = described_class.build(schema)
    resource = model[:resources].first
    update = resource[:actions].first
    expect(model[:actions]).to include(update)
    expect(model[:actions].find { |item| item[:accessor_name] == 'update' }).to equal(update)
    expect(update[:aliases]).to eq(['change'])
    expect(update[:path_template]).to eq('/widgets/{widget_id}')
    expect(resource[:children].first[:actions].first.values_at(:export_name, :placeholders))
      .to eq(['Widget__Part__Show', %w[widget_id part_id]])
    expect { update[:input][:parameters].first[:wire_name].replace('changed') }.to raise_error(FrozenError)
  end

  it 'preserves all eight kinds, null flags, filters, associations and metadata roles' do
    schema = snapshot
    fields = described_class::TYPES.to_h { |kind| [kind.downcase, parameter(kind, nullable: true)] }
    fields['resource'].merge!('resource' => ['widget'], 'value_id' => 'id', 'value_label' => 'name')
    item = fixture_action(schema)
    item['input'] = io(fields.merge('limit' => parameter('Integer')))
    item['meta'] = { 'global' => { 'input' => io('count' => parameter('Boolean')) },
                     'object' => { 'output' => io('revision' => parameter('Integer')) } }
    result = described_class.build(schema)[:actions].first
    expect(result[:input][:parameters].map { |field| field[:kind] }).to include(*described_class::TYPES)
    expect(result[:input][:parameters].find { |field| field[:kind] == 'Resource' }[:association])
      .to eq(resource_path: ['widget'], value_id: 'id', value_label: 'name')
    expect(result[:global_input][:parameters].first[:wire_name]).to eq('count')
    expect(result[:object_output][:parameters].first[:wire_name]).to eq('revision')
  end

  it 'counts authentication separately while still validating it' do
    schema = snapshot
    schema['description']['authentication']['token'] = { 'resources' => { 'token' => {
      'resources' => {}, 'actions' => { 'request' => action(path: '/api/_auth/token', method: 'POST') }
    } } }
    expect(described_class.build(schema)[:actions].length).to eq(1)
    schema['description']['authentication']['token']['resources']['token']['actions']['request']['input']['parameters']['bad'] = parameter('Future')
    expect { described_class.build(schema) }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{authentication/token/token/request/input/bad})
  end

  it 'rejects unsupported actual schema constructs with precise paths' do
    changes = [
      ->(item) { item['input']['parameters']['bad'] = parameter('Future') },
      ->(item) { item['input']['layout'] = 'object_list' },
      ->(item) { item['input']['format'] = {} },
      ->(item) { item['output']['namespace'] = false },
      ->(item) { item['path'] = '/api/_auth/wrong-application-route' },
      ->(item) { item['path'] = '/api/v1.0/%2e%2e/widgets' }
    ]
    changes.each do |change|
      schema = snapshot
      change.call(fixture_action(schema))
      expect { described_class.build(schema) }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{widget/(?:actions/)?update})
    end
  end

  it 'rejects collisions among aliases, children, normalized fields and reserved helpers' do
    schema = snapshot
    fixture_action(schema)['aliases'] = ['then']
    expect { described_class.build(schema) }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{reserved helper then.*widget/update/alias/then})
    schema = snapshot
    fixture_action(schema)['input']['parameters'] = { 'a-b' => parameter, 'a_b' => parameter }
    expect { described_class.build(schema) }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{widget/update/input/a-b.*widget/update/input/a_b})
    schema = snapshot
    schema['description']['resources']['widget']['resources']['update'] = { 'resources' => {}, 'actions' => {} }
    expect { described_class.build(schema) }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{collision.*widget/update})
  end

  it 'reserves emitted declarations without reserving unused export-name bases' do
    schema = snapshot
    schema['description']['resources']['widget_resource'] = { 'resources' => {}, 'actions' => {} }
    result = described_class.build(schema)
    expect(result[:resources].map { |resource| resource[:export_name] }).to eq(%w[Widget WidgetResource])
    schema['description']['resources']['widgetResource'] = { 'resources' => {}, 'actions' => {} }
    expect { described_class.build(schema) }.to raise_error(HaveAPI::TypeScriptClient::Error, /WidgetResourceResource.*widgetResource.*widget_resource/)
  end

  it 'normalizes null parameter flags used by HaveAPI resource descriptions to false' do
    schema = snapshot
    fixture_action(schema)['input']['parameters']['name'].merge!('required' => nil, 'nullable' => nil, 'protected' => nil)
    field = described_class.build(schema)[:actions].first[:input][:parameters].first
    expect(field.values_at(:required, :nullable, :protected)).to eq([false, false, false])
    fixture_action(schema)['input']['parameters']['name']['required'] = 'yes'
    expect { described_class.build(schema) }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{widget/update/input/name})
  end

  it 'rejects query object-input metadata before emitting an uncallable operation' do
    %w[GET OPTIONS].each do |method|
      [true, false].each do |required|
        schema = snapshot
        item = fixture_action(schema)
        item['method'] = method
        item['meta']['object'] = { 'input' => io('revision' => parameter('Integer', required:)) }
        expect { described_class.build(schema) }
          .to raise_error(HaveAPI::TypeScriptClient::Error, %r{unsupported query object-input metadata at widget/update/meta/object/input})
      end
    end
  end
end
