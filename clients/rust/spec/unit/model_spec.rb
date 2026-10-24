require 'spec_helper'

describe HaveAPI::RustClient::Model do
  include RustGeneratorFixtures

  let(:model) { Object.new.extend(described_class) }
  let(:config) do
    { 'crate_name' => 'fixture-client', 'crate_version' => '0.1.0', 'license' => 'MIT',
      'edition' => '2024', 'rust_version' => '1.95', 'rustfmt_version' => 'not invoked' }
  end

  it 'permits omission only for documentation while keeping generation versions required' do
    expect(described_class.validate_package(crate_name: 'fixture-client')).to be_nil
    expect { described_class.validate_package(crate_name: 'fixture-client', required_version: true) }
      .to raise_error(HaveAPI::RustClient::Error)
    expect { HaveAPI::RustClient::Generator.new(schema: snapshot, config: config.merge('crate_version' => nil)) }
      .to raise_error(HaveAPI::RustClient::Error)
  end

  it 'keeps the actual generator full configuration contract' do
    expect(HaveAPI::RustClient::Generator.validate_config(config)).to be_nil
    expect { HaveAPI::RustClient::Generator.validate_config(config.except('rustfmt_version')) }
      .to raise_error(HaveAPI::RustClient::Error, /config/)
    %w[license edition rust_version rustfmt_version].each do |key|
      expect { HaveAPI::RustClient::Generator.validate_config(config.merge(key => '')) }
        .to raise_error(HaveAPI::RustClient::Error)
    end
  end

  it 'preserves input/output Rust types including Resource associations' do
    { 'String' => 'String', 'Text' => 'String', 'Datetime' => 'String', 'Integer' => 'i64',
      'Resource' => 'i64', 'Float' => 'f64', 'Boolean' => 'bool', 'Custom' => 'serde_json::Value' }.each do |type, expected|
      field = { desc: parameter(type) }
      expect(model.rust_type(field)).to eq(expected)
      expect(model.rust_type(field, output: true)).to eq(type == 'Resource' ? 'runtime::Association' : expected)
    end
    generator = HaveAPI::RustClient::Generator.new(schema: snapshot, config:)
    expect(generator.rust_type({ desc: parameter('Resource') })).to eq('i64')
  end

  it 'merges sorted object/global metadata but leaves list object metadata nested' do
    field = ->(name, type) { { name:, desc: parameter(type) } }
    shared = field.call('shared', 'Integer')
    action = { global_output: { parameters: [shared, field.call('z', 'Boolean')] },
               object_output: { parameters: [shared, field.call('a', 'String')] }, output: { layout: 'object' } }
    expect(model.meta_parameters(action).map { |item| item[:name] }).to eq(%w[a shared z])
    action[:output][:layout] = 'object_list'
    expect(model.meta_parameters(action).map { |item| item[:name] }).to eq(%w[shared z])
    action[:output] = nil
    expect(model.meta_parameters(action).map { |item| item[:name] }).to eq(%w[shared z])
  end

  it 'rejects incompatible duplicate metadata definitions' do
    action = { global_output: { parameters: [{ name: 'count', desc: parameter('Integer') }] },
               object_output: { parameters: [{ name: 'count', desc: parameter('String') }] }, output: { layout: 'object' } }
    expect { model.meta_parameters(action) }.to raise_error(HaveAPI::RustClient::Error, /inconsistent metadata/)
  end
end
