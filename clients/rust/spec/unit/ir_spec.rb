require_relative '../spec_helper'

RSpec.describe HaveAPI::RustClient::IR do
  include RustGeneratorFixtures

  it 'preserves all eight parameter kinds and tri-state flags' do
    parameters = described_class::TYPES.to_h { |type| [type.downcase, parameter(type, nullable: true)] }
    model = described_class.new(snapshot(actions: { 'update' => action(input: io(parameters)) }))
    expect(model.actions.first[:input][:parameters].map { |field| field[:desc]['type'] }).to match_array(described_class::TYPES)
    expect(model.inventory.fetch('parameter_count')).to eq(10)
  end

  it 'fails unknown field types and layouts with the schema path' do
    expect do
      described_class.new(snapshot(actions: { 'update' => action(input: io('bad' => parameter('FutureType'))) }))
    end.to raise_error(HaveAPI::RustClient::Error, %r{widget/update/input/bad})
    expect do
      described_class.new(snapshot(actions: { 'update' => action(input: io({}, layout: 'future')) }))
    end.to raise_error(HaveAPI::RustClient::Error, /unsupported layout/)
  end

  it 'supports unnamespaced object input and rejects unnamespaced outputs/list inputs' do
    expect(described_class.new(snapshot(actions: { 'update' => action(input: io({}, namespace: false)) })).actions.first[:input][:namespace]).to be_nil
    expect do
      described_class.new(snapshot(actions: { 'update' => action(output: io({}, namespace: false)) }))
    end.to raise_error(HaveAPI::RustClient::Error, /output namespace=false/)
    expect do
      described_class.new(snapshot(actions: { 'update' => action(input: io({}, namespace: false, layout: 'object_list')) }))
    end.to raise_error(HaveAPI::RustClient::Error, /unnamespaced list/)
  end

  it 'rejects collisions after normalization and nullable setter allocation' do
    %w[foo-bar foo_bar].then do |names|
      parameters = names.to_h { |name| [name, parameter] }
      expect do
        described_class.new(snapshot(actions: { 'update' => action(input: io(parameters)) }))
      end.to raise_error(HaveAPI::RustClient::Error, /foo-bar.*foo_bar/)
    end
    expect do
      described_class.new(snapshot(actions: { 'update' => action(input: io('name' => parameter(nullable: true), 'name_null' => parameter)) }))
    end.to raise_error(HaveAPI::RustClient::Error, /collision/)
  end

  it 'rejects input setters that collide with common request methods' do
    %w[new input global_meta object_meta send input_mut prepared].each do |name|
      expect do
        described_class.new(snapshot(actions: { 'update' => action(input: io(name => parameter)) }))
      end.to raise_error(HaveAPI::RustClient::Error, %r{reserved member #{name} and widget/update/input/#{name}})
    end
  end

  it 'rejects resource accessors that collide with common client methods' do
    %w[builder config].each do |name|
      schema = snapshot
      schema.fetch('description').fetch('resources')[name] = { 'actions' => {}, 'resources' => {} }
      expect do
        described_class.new(schema)
      end.to raise_error(HaveAPI::RustClient::Error, /reserved member #{name} and #{name}/)
    end
  end

  it 'rejects placeholder arguments that shadow generated request locals' do
    expect do
      described_class.new(snapshot(actions: { 'update' => action(path: '/v1.0/widgets/{path_params}') }))
    end.to raise_error(HaveAPI::RustClient::Error, %r{reserved member path_params and widget/update/path_params})
  end

  it 'preserves nested component boundaries and binds parent placeholders once' do
    schema = snapshot
    root = schema.fetch('description').fetch('resources')
    root['widget']['resources']['part'] = { 'actions' => {
      'show' => action(path: '/v1.0/widgets/{widget_id}/parts/{part_id}')
    }, 'resources' => {} }
    root['widget_part'] = { 'actions' => {}, 'resources' => {} }
    model = described_class.new(schema)
    nested = model.resources.find { |resource| resource[:path] == %w[widget part] }
    expect(nested[:module]).to eq('widget__part')
    expect(nested[:bound]).to eq(['widget_id'])
    expect(model.resources.map { |resource| resource[:module] }).to include('widget_part')
  end

  it 'rejects unsafe action paths and another API version' do
    %w[https://evil.test/path //evil.test/path /v2.0/widgets /v1.0/../widgets /v1.0/%2e%2e/widgets].each do |path|
      expect do
        described_class.new(snapshot(actions: { 'update' => action(path:) }))
      end.to raise_error(HaveAPI::RustClient::Error)
    end
  end

  it 'escapes source strings and Rust reserved identifiers' do
    expect(HaveAPI::RustClient::Naming.snake('type')).to eq('type_')
    expect(HaveAPI::RustClient::Naming.literal("\";panic!();\\\n\u0001")).to eq('"\";panic!();\\\\\n\u{1}"')
  end
end
