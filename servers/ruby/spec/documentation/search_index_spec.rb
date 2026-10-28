require 'spec_helper'

RSpec.describe HaveAPI::DocumentationSearch::Index do
  let(:description) do
    { resources: { widget: { label: 'Widget label', resources: {}, actions: {
      show: { method: 'GET', path: '/v1/widgets/{id}', aliases: ['find'], label: 'Show widget',
              input: { parameters: { name: { type: 'String', label: 'Name' } } },
              output: { parameters: { id: { type: 'Integer', label: 'Identifier' } } } }
    } } }, authentication: {} }
  end
  let(:options) { { base_path: '/v1/', version: '1', locale: 'en', visibility: 'anonymous' } }

  def index(source = description, **changes)
    described_class.new(description: source, **options, **changes)
  end

  it 'fingerprints deterministic owned payload bytes and preserves parent references without source mutation' do
    before = Marshal.dump(description)
    first = index
    serialized = JSON.parse(JSON.generate(description))
    expect(index(serialized).payload).to eq(first.payload)
    expect(index(serialized).key).to eq(first.key)
    expect(first.key).to eq(Digest::SHA256.hexdigest(JSON.generate(first.payload)))
    expect(first.payload).to be_frozen
    expect(first.payload[:parameters]).to all(be_frozen)
    expect(first.payload[:actions].first[:resource]).to eq(0)
    expect(first.payload[:parameters].map { |parameter| parameter[:action] }).to eq([0, 0])
    expect(Marshal.dump(description)).to eq(before)
    expect(description[:resources][:widget][:label]).not_to be_frozen
  end

  it 'sorts each metadata collection independently of the caller hash order' do
    source = Marshal.load(Marshal.dump(description))
    source[:resources][:another] = { actions: {}, resources: {} }
    reversed = source.merge(resources: source[:resources].to_a.reverse.to_h)
    expect(index(source).key).to eq(index(reversed).key)
  end

  it 'changes keys for every supported visible input and version, mount, locale or visibility boundary' do
    original = index.key
    mutations = [
      ->(source) { source[:resources][:extra] = { actions: {} } },
      ->(source) { source[:resources][:widget][:label] = 'Changed label' },
      ->(source) { source[:resources][:widget][:actions][:extra] = { method: 'POST' } },
      ->(source) { source[:resources][:widget][:actions][:show][:aliases] = ['lookup'] },
      ->(source) { source[:resources][:widget][:actions][:show][:path] = '/changed' },
      ->(source) { source[:resources][:widget][:actions][:show][:input][:parameters][:extra] = { type: 'Boolean' } },
      ->(source) { source[:resources][:widget][:actions][:show][:output][:parameters][:id][:label] = 'Changed identifier' }
    ]
    mutations.each do |mutate|
      source = Marshal.load(Marshal.dump(description))
      mutate.call(source)
      expect(index(source).key).not_to eq(original)
    end
    [{ version: '2' }, { base_path: '/mounted/v1/' }, { locale: 'cs' }, { visibility: 'authenticated' }].each do |change|
      expect(index(**change).key).not_to eq(original)
    end
  end

  it 'projects only whitelisted strings and no prose, defaults, examples, validator values, identities or private fields' do
    source = Marshal.load(Marshal.dump(description))
    source[:private_generator_model] = 'PRIVATE'
    source[:current_user] = { login: 'ACCOUNT' }
    source[:csrf] = 'CSRF'
    source[:resources][:widget][:description] = 'PROSE'
    action = source[:resources][:widget][:actions][:show]
    action[:examples] = [{ request: 'EXAMPLE' }]
    action[:input][:parameters][:name].merge!(default: 'DEFAULT', validators: { include: { values: ['VALIDATOR'] } })
    expect(index(source).key).to eq(index.key)
    expect(JSON.generate(index(source).payload)).not_to include('PRIVATE', 'ACCOUNT', 'CSRF', 'PROSE', 'EXAMPLE', 'DEFAULT', 'VALIDATOR')
  end

  it 'keeps the full index beyond the result cap and produces the shared Ruby/browser ordering fixture' do
    fixture = JSON.parse(File.read(File.join(__dir__, 'fixtures/search_index.json')))
    expect(fixture.fetch('index').fetch('parameters').length).to be > 20
    fixture.fetch('queries').each do |query|
      result = HaveAPI::DocumentationSearch.new(index: fixture.fetch('index'), query: query.fetch('query')).call
      identities = result[:results].map do |record|
        [record[:kind], record[:authentication], record[:resource_path].join('.'), record[:action_name], record[:direction], record[:name]].join(':')
      end
      expect(identities).to eq(query.fetch('expected'))
      expect(result[:more]).to eq(query.fetch('more'))
    end
  end
end
