require 'spec_helper'

describe HaveAPI::ClientExample::Context do
  let(:description) { { resources: { widget: { actions: {} } } } }
  let(:context) do
    described_class.new(version: '1', host: 'api.test', base_url: 'https://api.test/mount/',
                        version_url: 'https://api.test/mount/v1/', description:)
  end

  it 'copies and freezes request data without freezing the source description' do
    expect(context.description).to be_frozen
    expect(context.description[:resources]).to be_frozen
    expect(description[:resources]).not_to be_frozen
    description[:resources][:secret] = {}
    expect(context.description[:resources]).not_to have_key(:secret)
  end

  it 'keeps per-example state independent and leaves the original context intact' do
    data = { request: { name: 'safe' } }
    child = context.with(resource_path: ['widget'], action_name: 'show', sample: data)
    data[:request][:name].replace('changed')
    expect(child.sample[:request][:name]).to eq('safe')
    expect(context.sample).to be_nil
    expect(child.resource_path).to eq(['widget'])
    expect(child).to be_frozen
  end

  it 'defaults to simple and shares owned data when changing the detail' do
    expect(context.detail).to eq(:simple)
    thorough = context.with(detail: :thorough)
    expect(thorough.detail).to eq(:thorough)
    expect(thorough).to be_frozen
    (described_class::FIELDS - [:detail]).each do |field|
      expect(thorough.public_send(field)).to equal(context.public_send(field))
    end
    expect(thorough.with(detail: :simple).detail).to eq(:simple)
    expect(context.detail).to eq(:simple)
  end

  it 'rejects detail values outside the two explicit symbols in construction and derivation' do
    [nil, false, 'simple', 'thorough', :unknown].each do |detail|
      expect { context.with(detail:) }.to raise_error(ArgumentError, 'detail must be :simple or :thorough')
      expect do
        described_class.new(version: '1', host: 'api.test', base_url: '/', version_url: '/v1/', description: {}, detail:)
      end.to raise_error(ArgumentError, 'detail must be :simple or :thorough')
    end
  end

  describe '#with' do
    let(:fields) do
      {
        version: 1, host: 'api.test', base_url: 'https://api.test/mount/',
        version_url: 'https://api.test/mount/v1/',
        description: { 'resources' => { 'widget' => { 'label' => 'Widget' } } },
        resource_path: [:widget, 2], resource: { 'label' => 'Widget' },
        action_name: :show, action: { 'method' => 'GET' },
        sample: { 'request' => { 'values' => [0, false, '', nil] } }, profile: Object.new, detail: :simple
      }
    end
    let(:parent) { described_class.new(**fields) }
    let(:replacements) do
      {
        version: 2, host: 'other.test', base_url: 'https://other.test/api/',
        version_url: 'https://other.test/api/v2/',
        description: { 'resources' => { 'other' => { 'label' => 'Other' } } },
        resource_path: [:other, 3], resource: { 'label' => 'Other' },
        action_name: :update, action: { 'method' => 'POST' },
        sample: { 'request' => { 'values' => [false, 0, nil, ''] } },
        profile: Object.new, detail: :thorough
      }
    end

    it 'returns a distinct frozen context sharing every unchanged field' do
      child = parent.with

      expect(child).not_to equal(parent)
      expect(child).to be_frozen
      described_class::FIELDS.each do |field|
        expect(child.public_send(field)).to equal(parent.public_send(field))
      end
      expect(child.description['resources']['widget']).to equal(parent.description['resources']['widget'])
    end

    HaveAPI::ClientExample::Context::FIELDS.each do |field|
      it "normalizes an explicit #{field} replacement like the constructor and shares other fields" do
        changed = { field => replacements.fetch(field) }
        child = parent.with(**changed)
        constructor = described_class.new(**fields, **changed)

        expect(child).to be_frozen
        expect(child.public_send(field)).to eq(constructor.public_send(field))
        (described_class::FIELDS - [field]).each do |unchanged|
          expect(child.public_send(unchanged)).to equal(parent.public_send(unchanged))
        end
        expect(parent.public_send(field)).to eq(described_class.new(**fields).public_send(field))
      end
    end

    it 'copies supplied nested containers and strings even when their outer hash is frozen' do
      key = ['mutable key']
      source = { key => [{ 'value' => 'safe' }] }.freeze
      child = parent.with(description: source, resource: source, action: source, sample: source)

      %i[description resource action sample].each do |field|
        owned = child.public_send(field)
        expect(owned).not_to equal(source)
        expect(owned).to be_frozen
        expect(owned.keys.first).not_to equal(key)
        expect(owned.keys.first).to be_frozen
        expect(owned.keys.first.first).to be_frozen
        expect(owned.values.first).to be_frozen
        expect(owned.values.first.first).to be_frozen
        expect(owned.values.first.first.keys.first).to be_frozen
        expect(owned.values.first.first['value']).to be_frozen
      end
      expect(key).not_to be_frozen
      expect(key.first).not_to be_frozen
      expect(source.values.first).not_to be_frozen
      expect(source.values.first.first['value']).not_to be_frozen
      key.first.replace('changed key')
      source.values.first.first['value'].replace('changed')
      %i[description resource action sample].each do |field|
        expect(child.public_send(field)).to eq(['mutable key'] => [{ 'value' => 'safe' }])
      end
    end

    it 'detaches explicitly supplied strings and converts resource path elements without retaining them' do
      text = +'value'
      path = [text, :widget, 7]
      child = parent.with(version: text, host: text, base_url: text, version_url: text,
                          resource_path: path, action_name: text)

      %i[version host base_url version_url action_name].each do |field|
        expect(child.public_send(field)).to eq('value')
        expect(child.public_send(field)).not_to equal(text)
        expect(child.public_send(field)).to be_frozen
      end
      expect(child.resource_path).to eq(%w[value widget 7])
      expect(child.resource_path).to be_frozen
      expect(child.resource_path).not_to equal(path)
      expect(child.resource_path).to all(be_frozen)
      expect(path).not_to be_frozen
      expect(text).not_to be_frozen
      text.replace('changed')
      path << 'extra'
      expect(child.version).to eq('value')
      expect(child.resource_path).to eq(%w[value widget 7])
    end

    it 'copies explicitly supplied owned values again instead of treating frozen data as trusted' do
      child = parent.with(description: parent.description, resource_path: parent.resource_path,
                          sample: parent.sample)

      %i[description resource_path sample].each do |field|
        expect(child.public_send(field)).to eq(parent.public_send(field))
        expect(child.public_send(field)).not_to equal(parent.public_send(field))
      end
      expect(child.description['resources']).not_to equal(parent.description['resources'])
      expect(child.sample['request']['values']).not_to equal(parent.sample['request']['values'])
    end

    it 'keeps parent, sibling and chained derivations detached from their supplied inputs' do
      data = { request: { name: 'safe' } }
      child = parent.with(sample: data)
      sibling = parent.with(sample: data)
      grandchild = child.with(action_name: :update)
      fields[:description]['resources']['widget']['label'].replace('changed source')
      data[:request][:name].replace('changed sample')

      expect(parent.description['resources']['widget']['label']).to eq('Widget')
      expect(child.description).to equal(parent.description)
      expect(sibling.description).to equal(parent.description)
      expect(grandchild.description).to equal(parent.description)
      expect(parent.sample).to eq('request' => { 'values' => [0, false, '', nil] })
      expect(child.sample).to eq(request: { name: 'safe' })
      expect(sibling.sample).to eq(child.sample)
      expect(sibling.sample).not_to equal(child.sample)
      expect(grandchild.sample).to equal(child.sample)
      expect(child.action_name).to eq('show')
      expect(grandchild.action_name).to eq('update')
      expect { child.sample[:request][:name].replace('forbidden') }.to raise_error(FrozenError)
    end

    it 'distinguishes omitted fields from explicit nil replacements' do
      child = parent.with(description: nil, resource: nil, action_name: nil, action: nil, sample: nil, profile: nil)

      %i[description resource action_name action sample profile].each do |field|
        expect(child.public_send(field)).to be_nil
        expect(parent.public_send(field)).not_to be_nil
      end
      expect(child.version).to equal(parent.version)
      expect(parent.with(version: nil, host: nil, base_url: nil, version_url: nil))
        .to have_attributes(version: '', host: '', base_url: '', version_url: '')
      expect(context.with.action_name).to be_nil
    end

    it 'shares arbitrary profiles and non-container leaves without freezing them' do
      leaf = Object.new
      profile = fields.fetch(:profile)
      child = parent.with(description: { custom: leaf }, profile: leaf)

      expect(parent.profile).to equal(profile)
      expect(parent.with.profile).to equal(profile)
      expect(profile).not_to be_frozen
      expect(child.profile).to equal(leaf)
      expect(child.description[:custom]).to equal(leaf)
      expect(leaf).not_to be_frozen
    end

    it 'continues rejecting invalid resource paths' do
      expect { parent.with(resource_path: nil) }.to raise_error(NoMethodError)
      expect { described_class.new(**fields, resource_path: nil) }.to raise_error(NoMethodError)
      expect(parent.resource_path).to eq(%w[widget 2])
    end

    it 'rejects unknown keywords before normalizing any supplied values' do
      value = Object.new
      allow(value).to receive(:to_s).and_call_original

      expect { parent.with(version: value, unknown: true) }.to raise_error(ArgumentError, 'unknown keyword: :unknown')
      expect { parent.with(unknown: true, other: false) }
        .to raise_error(ArgumentError, 'unknown keywords: :unknown, :other')
      expect { parent.with('version' => '2') }.to raise_error(ArgumentError, 'unknown keyword: "version"')
      expect(value).not_to have_received(:to_s)
      expect(parent).not_to respond_to(:unknown)
      expect(parent.version).to eq('1')
    end

    it 'keeps subclass constructors, extra keywords and constructor effects on every derivation' do
      subclass = Class.new(described_class) do
        attr_reader :marker, :initializations

        def initialize(marker: :default, initializations: 0, **fields)
          @marker = marker
          @initializations = initializations + 1
          super(**fields)
        end
      end
      original = subclass.new(**fields, marker: :original)
      child = original.with(marker: :child, initializations: original.initializations)
      defaulted = original.with

      expect(child).to be_a(subclass)
      expect(child).to be_frozen
      expect(child.marker).to eq(:child)
      expect(child.initializations).to eq(2)
      expect(defaulted.marker).to eq(:default)
      expect(original.marker).to eq(:original)
      expect(original.initializations).to eq(1)
      expect(child.description).to eq(original.description)
      expect(child.description).not_to equal(original.description)
    end
  end

  it 'preserves legacy initialization constructors and wraps plain source' do
    renderer = Class.new(HaveAPI::ClientExample) do
      def initialize(host, base_url, version)
        raise ArgumentError, 'expected API version 1' unless version == '1'

        super
      end

      def init
        "#{base_url}v#{version}/"
      end
    end
    result = renderer.render(:init, context:)
    expect(result).to eq(status: :code, code: 'https://api.test/mount/v1/')
    expect(result).to be_frozen
    expect(result[:code]).to be_frozen
  end

  it 'preserves request/response renderers and nil legacy authentication' do
    renderer = Class.new(HaveAPI::ClientExample) do
      def request(_sample)
        'request'
      end

      def response(_sample)
        'response'
      end
    end
    expect(renderer.render(:example, context:)).to eq(status: :code, code: "request\n\nresponse")
    expect(renderer.render(:auth, context:, auth_method: :basic, auth_description: {})).to be_nil
  end

  it 'wraps a limitation without allowing HTML or an invalid result contract' do
    renderer = Class.new(HaveAPI::ClientExample) do
      def init
        { status: :limitation, reason: 'Cannot render <this>' }
      end
    end
    expect(renderer.render(:init, context:)).to eq(status: :limitation, reason: 'Cannot render <this>')
  end
end
