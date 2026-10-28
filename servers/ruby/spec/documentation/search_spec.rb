require 'spec_helper'

RSpec.describe HaveAPI::DocumentationSearch do
  let(:action) do
    { method: 'POST', path: '/v1/widgets/{id}/renew', aliases: ['extend'],
      input: { parameters: { lifetime: { label: 'Lease duration', type: 'Integer', default: 'DEFAULT_SECRET',
                                         validators: { include: { values: ['VALIDATOR_SECRET'] } } } } },
      output: { parameters: { valid_to: { label: 'Expires at', type: 'Datetime' } } },
      description: 'DESCRIPTION_SECRET', examples: [{ request: { name: 'EXAMPLE_SECRET' } }] }
  end
  let(:description) do
    { resources: { widget: { actions: { renew: action }, resources: {} } },
      authentication: { token: { resources: { token: { actions: { request: action }, resources: {} } } } } }
  end
  let(:presentation) { Object.new.extend(described_class::Helpers) }

  def search(query, source = description)
    index = described_class::Index.new(description: source, base_path: '/v1/', version: '1', locale: 'en', visibility: 'anonymous')
    described_class.new(index: index.payload, query:).call
  end

  it 'uses complete resource identities and ancestor labels without changing the index' do
    fixture = JSON.parse(File.read(File.join(__dir__, 'fixtures/search_index.json')))
    index = fixture.fetch('index')
    before = JSON.generate(index)
    fixture.fetch('display_queries').each do |query|
      results = described_class.new(index:, query: query.fetch('query')).call[:results]
      display = results.map do |result|
        { 'title' => "#{result[:kind].to_s.capitalize}: #{presentation.documentation_search_result_title(result)}",
          'context' => presentation.documentation_search_result_context(result) }
      end
      expect(display).to eq(query.fetch('expected'))
    end
    expect(JSON.generate(index)).to eq(before)
  end

  it 'keeps ancestor labels within their provider and omits an identical resource context' do
    source = { resources: { token: { label: 'Public tokens', resources: { child: { label: 'Public child' } } },
                            same: { label: 'same' } },
               authentication: { token: { resources: { token: { label: 'Private tokens',
                                                                resources: { child: { label: 'Private child' } } } } } } }
    results = search('child', source)[:results]
    labels = results.map { |result| [result[:authentication], result[:resource_label]] }
    expect(labels).to eq([[nil, 'Public tokens / Public child'], ['token', 'Private tokens / Private child']])
    same = search('same', source)[:results].first
    expect(presentation.documentation_search_result_context(same)).to eq([])
  end

  it 'uses machine segments when a compact fixture omits an ancestor record' do
    index = { resources: [{ path: %w[parent child], label: 'Child label', search: ['child'] }], actions: [], parameters: [] }
    result = described_class.new(index:, query: 'child').call[:results].first
    expect(result[:resource_label]).to eq('parent / Child label')
    expect(presentation.documentation_search_result_title(result)).to eq('parent.child')
  end

  it 'matches all case-insensitive query tokens across parent and selected metadata' do
    result = search('WIDGET lease INTEGER')
    expect(result[:results]).to include(include(kind: :parameter, name: 'lifetime', direction: :input,
                                                type: 'Integer', resource_path: ['widget'], action_name: 'renew'))
    expect(search('extend POST')[:results]).to include(include(kind: :action, name: 'renew'))
    expect(search('/v1/widgets/{id}/renew')[:results]).to include(include(kind: :action, name: 'renew'))
    expect(search('Expires')[:results]).to include(include(name: 'valid_to', direction: :output, type: 'Datetime'))
  end

  it 'excludes examples, defaults, validators, arbitrary prose and provider credentials' do
    source = Marshal.load(Marshal.dump(description))
    source[:authentication][:token][:password] = 'CREDENTIAL_SECRET'
    %w[DEFAULT_SECRET VALIDATOR_SECRET DESCRIPTION_SECRET EXAMPLE_SECRET CREDENTIAL_SECRET].each do |query|
      expect(search(query, source)[:results]).to eq([])
    end
  end

  it 'ranks exact machine matches before prefixes and remaining token matches with deterministic ties' do
    tree = %w[widget_long mywidget widget].reverse.to_h do |name|
      [name, { actions: {}, resources: {} }]
    end
    source = { resources: tree }
    expect(search('widget', source)[:results].map { |result| result[:name] }).to eq(%w[widget widget_long mywidget])
    reverse = { resources: tree.to_a.reverse.to_h }
    expect(search('widget', reverse)).to eq(search('widget', source))
  end

  it 'prioritizes resources, actions and parameters before match strength within each kind' do
    source = { resources: { mywidget: { actions: {
      widget: { input: { parameters: { widget: { type: 'String' } } } },
      widget_long: { input: { parameters: { widget_long: { type: 'String' } } } }
    } }, widget: { actions: {} } } }
    results = search('widget', source)[:results]
    expect(results.map { |result| [result[:kind], result[:name]] }).to eq([
                                                                            [:resource, 'widget'], [:resource, 'mywidget'],
                                                                            [:action, 'widget'], [:action, 'widget_long'],
                                                                            [:parameter, 'widget'], [:parameter, 'widget_long']
                                                                          ])
  end

  it 'caps returned matches at twenty and explicitly reports more without changing the source' do
    tree = 32.times.to_h { |index| ["widget#{index}", { actions: {}, resources: {} }] }
    source = { resources: tree }
    before = Marshal.dump(source)
    result = search('widget', source)
    expect(result[:results].length).to eq(20)
    expect(result[:more]).to be(true)
    expect(search('widget31', source)[:more]).to be(false)
    expect(search('absent', source)).to eq(query: 'absent', results: [], more: false)
    expect(Marshal.dump(source)).to eq(before)
  end

  it 'returns provider-resource matches only from the supplied filtered authentication tree' do
    results = search('token lifetime')[:results]
    expect(results).to contain_exactly(include(kind: :parameter, authentication: 'token', resource_path: ['token'],
                                               action_name: 'request', name: 'lifetime'))
    expect(search('token', description.merge(authentication: {}))[:results]).to eq([])
  end

  it 'supports serialized string keys and nested resource context without reading hidden trees' do
    source = JSON.parse(JSON.generate(description))
    source['resources']['parent'] = { 'actions' => {}, 'resources' => { 'child' => { 'actions' => { 'renew' => action } } } }
    expect(search('parent child duration', source)[:results]).to include(include(resource_path: %w[parent child], name: 'lifetime'))
  end

  it 'encodes every parameter anchor component unambiguously and uses it in result records' do
    arguments = { resource_path: %w[a b-c], action_name: 'show', direction: :input, parameter_name: 'x-y' }
    first = described_class.parameter_anchor(**arguments)
    variations = [arguments.merge(resource_path: %w[a-b c]), arguments.merge(action_name: 'show-input'),
                  arguments.merge(direction: :output), arguments.merge(parameter_name: 'x/y "ž"'),
                  arguments.merge(authentication: 'token')]
    anchors = [first] + variations.map { |value| described_class.parameter_anchor(**value) }
    expect(anchors.uniq.length).to eq(anchors.length)
    expect(anchors).to all(match(/\Aparameter-[0-9a-f]+\z/))
    record = search('widget lifetime')[:results].first
    expect(record[:anchor]).to eq(described_class.parameter_anchor(resource_path: ['widget'], action_name: 'renew',
                                                                   direction: :input, parameter_name: 'lifetime'))
  end
end
