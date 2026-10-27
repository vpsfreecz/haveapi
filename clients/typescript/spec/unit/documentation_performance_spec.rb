require_relative '../documentation/fixtures'

RSpec.describe HaveAPI::TypeScriptClient::Documentation do
  include TypeScriptDocumentationFixtures

  let(:schema) do
    documentation_snapshot.tap { |value| fixture_action(value)['auth'] = true }
  end
  let(:normalized_nodes) { [] }
  let(:adapter) do
    nodes = normalized_nodes
    # Instrument the class before construction so the real adapter stays frozen.
    Class.new(described_class) do
      define_method(:normalize) do |value|
        nodes << value.object_id
        super(value)
      end
      private :normalize
    end.from_snapshot(snapshot: schema, package_name: 'widget-client', package_version: '1.2.3')
  end

  def context_with_unrelated_descendants(size)
    context = documentation_context(schema)
    unrelated = {
      'resources' => size.times.to_h do |index|
        ["resource#{index}", { 'actions' => { 'ignored' => action },
                               'resources' => { 'nested' => { 'description' => ['unused'] * size } } }]
      end
    }
    description = context.description
    description['resources']['unrelated'] = unrelated
    description['resources']['widget']['resources']['unrelated'] = unrelated
    description['resources']['widget']['actions']['unrelated'] = { 'aliases' => ['other'], 'input' => unrelated }
    description['authentication']['unrelated'] = unrelated
    description['meta']['unrelated'] = unrelated
    context
  end

  def render_with_work(context, **options)
    renderer = adapter
    normalized_nodes.clear
    result = renderer.render(context:, **options)
    [result, normalized_nodes.length]
  end

  %w[update change].each do |name|
    it "bounds #{name} action and credential normalization by the selected subtrees" do
      contexts = [1, 64].map { |size| context_with_unrelated_descendants(size) }
      contexts.each { |context| context.action_name = name }
      small, large = contexts.map { |context| render_with_work(context, kind: :example) }

      expect(small.first[:status]).to eq(:code)
      expect(small.first[:code]).to include('api["widget"]["update"]', "runtime.authenticate('basic'")
      expect(large.first).to eq(small.first)
      expect(small.last).to be > 10
      expect(large.last).to eq(small.last)
    end
  end

  %i[basic token].each do |provider|
    it "bounds #{provider} authentication normalization while comparing the complete selected provider" do
      contexts = [1, 64].map do |size|
        context = context_with_unrelated_descendants(size)
        context.description['authentication'][provider.to_s]['resources'] = { 'login' => { 'description' => ['advertised'] } }
        context
      end
      results = contexts.map do |context|
        render_with_work(context, kind: :auth, auth_method: provider,
                                  auth_description: context.description['authentication'][provider.to_s])
      end

      expect(results.first.first[:status]).to eq(:code)
      expect(results.last.first).to eq(results.first.first)
      expect(results.first.last).to be >= 10
      expect(results.last.last).to eq(results.first.last)

      expect(adapter.render(kind: :auth, context: contexts.last, auth_method: provider, auth_description: {}))
        .to include(status: :limitation)
    end
  end

  it 'bounds unavailable action and provider lookups without retaining hidden descendants' do
    contexts = [1, 64].map { |size| context_with_unrelated_descendants(size) }
    contexts.each { |context| context.description['resources']['widget']['actions'].delete('update') }
    small, large = contexts.map { |context| render_with_work(context, kind: :example) }
    expect(small.first[:status]).to eq(:limitation)
    expect(large).to eq(small)

    small, large = contexts.map { |context| render_with_work(context, kind: :auth, auth_method: :unknown) }
    expect(small.first[:status]).to eq(:limitation)
    expect(large).to eq(small)
  end
end
