require 'spec_helper'

describe HaveAPI::ClientExample::Profiles do
  let(:schema) { HaveAPI::ClientExample.const_get(:StructuralSchema) }
  let(:data) { { description: 'data description', default: { examples: ['data example'] }, message: 'data message' } }
  let(:parameter) do
    { type: 'Custom', default: data, description: 'private prose', label: 'private label',
      validators: { include: { values: [data], message: 'private validation message' }, custom: data }, format: data }
  end
  let(:description) do
    action = { path: '/v1/widgets/', input: { layout: :hash, parameters: { default: parameter } },
               output: { parameters: {} }, meta: { global: { input: { parameters: { example: parameter } } } },
               description: 'private action prose', examples: [{ request: data }] }
    resource = { description: 'private resource prose', actions: { index: action }, resources: {} }
    { resources: { widget: resource }, authentication: { token: { description: 'private auth prose', resources: { token: resource } } } }
  end

  it 'copies structural locations and strips defaults and prose without changing the server description' do
    before = JSON.generate(description)
    result = schema.copy(description)
    action = result.dig('resources', 'widget', 'actions', 'index')
    expect(action).not_to have_key('description')
    expect(action).not_to have_key('examples')
    expect(result.dig('resources', 'widget')).not_to have_key('description')
    expect(result.dig('authentication', 'token')).not_to have_key('description')
    expect(action.dig('input', 'parameters', 'default')).not_to have_key('default')
    expect(action.dig('meta', 'global', 'input', 'parameters', 'example')).not_to have_key('default')
    expect(result.dig('authentication', 'token', 'resources', 'token', 'actions', 'index')).not_to have_key('examples')
    expect(JSON.generate(description)).to eq(before)
    expect(description).not_to be_frozen
    expect(result).to be_frozen
    expect(action.dig('input', 'parameters', 'default')).to be_frozen
  end

  it 'retains parameter names, layouts, associations and arbitrary validator/Custom data verbatim' do
    parameter[:resource] = %w[widget]
    parameter[:choices] = { path: '/v1/widgets/', method: 'GET' }
    result = schema.copy(description)
    copied = result.dig('resources', 'widget', 'actions', 'index', 'input', 'parameters', 'default')
    expect(copied).to include('type' => 'Custom', 'resource' => ['widget'], 'choices' => { 'path' => '/v1/widgets/', 'method' => 'GET' })
    expect(copied['format']).to eq(JSON.parse(JSON.generate(data)))
    expect(copied.dig('validators', 'include', 'values')).to eq([JSON.parse(JSON.generate(data))])
    expect(copied.dig('validators', 'custom')).to eq(JSON.parse(JSON.generate(data)))
    expect(copied.dig('validators', 'include')).not_to have_key('message')
    expect(result.dig('resources', 'widget', 'actions', 'index', 'input', 'layout')).to eq('hash')
    expect(result.dig('resources', 'widget', 'actions', 'index', 'path')).to eq('/v1/widgets/')
  end
end
