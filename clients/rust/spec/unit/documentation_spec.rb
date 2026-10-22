require 'spec_helper'
require 'haveapi/rust_client/documentation'

describe HaveAPI::RustClient::Documentation do
  include RustGeneratorFixtures

  let(:config) do
    { 'crate_name' => 'fixture-client', 'crate_version' => '0.1.0', 'license' => 'MIT',
      'edition' => '2024', 'rust_version' => '1.95', 'rustfmt_version' => 'not invoked by documentation' }
  end
  let(:schema) { snapshot }
  let(:adapter) { described_class.new(snapshot: schema, config:) }
  let(:context_type) do
    Struct.new(:version, :base_url, :description, :resource_path, :action_name, :sample)
  end
  let(:context) do
    context_type.new(version: '1.0', base_url: 'https://example.test/', description: schema['description'],
                     resource_path: ['widget'], action_name: 'update',
                     sample: { path_params: [1], request: { name: 'widget' }, response: { id: 1 }, status: true })
  end

  def render(mode = :async, kind = :example, **options)
    adapter.render(kind:, context:, mode:, **options)
  end

  it 'constructs and renders without acquisition, generation, subprocesses or writes' do
    generator = HaveAPI::RustClient::Generator.new(schema:, config:)
    allow(HaveAPI::RustClient::Generator).to receive(:new).and_return(generator)
    allow(generator).to receive(:generate)
    allow(HaveAPI::RustClient::Snapshot).to receive(:fetch)
    allow(Open3).to receive(:capture3)
    allow(File).to receive(:write)
    expect(render).to include(status: :code)
    expect(HaveAPI::RustClient::Snapshot).not_to have_received(:fetch)
    expect(generator).not_to have_received(:generate)
    expect(Open3).not_to have_received(:capture3)
    expect(File).not_to have_received(:write)
  end

  it 'uses canonical IR mappings and independently pinned crate dependency' do
    resolved = adapter.resolve(resource_path: ['widget'], action_name: 'update')
    expected = HaveAPI::RustClient::IR.new(schema).actions.first
    expect(resolved[:method]).to eq(expected[:method])
    expect(render[:code]).to include('use fixture_client::Client;', 'version = "0.1.0"',
                                     'api.widget().update("1").name("widget".to_owned()).send().await?',
                                     'response.output.id', 'response.meta')
  end

  it 'preserves nullable, zero, false, empty and omitted inputs with real setters' do
    schema['description']['resources']['widget']['actions']['update']['input'] = io(
      'type' => parameter('String', nullable: true), 'count' => parameter('Integer'),
      'enabled' => parameter('Boolean'), 'name' => parameter, 'omitted' => parameter
    )
    context.sample[:request] = { type: nil, count: 0, enabled: false, name: '' }
    expect(render[:code]).to include('.type__null().count(0_i64).enabled(false).name("".to_owned())')
    expect(render[:code]).not_to include('.omitted(')
  end

  it 'uses explicit list InputValue fields and leaves absent fields unset' do
    schema['description']['resources']['widget']['actions']['update']['input']['layout'] = 'object_list'
    context.sample[:request] = [{ name: nil }, { name: '' }, {}]
    expect(render[:code]).to include('fixture_client::resources::widget::update::Input {',
                                     'name: fixture_client::InputValue::Null',
                                     'fixture_client::InputValue::Value("".to_owned())',
                                     '..Default::default()', '.input(input).send().await?')
  end

  it 'uses the full SDK naming scope and fails a saved collision at construction' do
    fields = schema['description']['resources']['widget']['actions']['update']['input']['parameters']
    fields['name!'] = parameter
    fields['name?'] = parameter
    expect { adapter }.to raise_error(HaveAPI::RustClient::Error, /collision/)
  end

  it 'binds nested ancestor and action arguments in route order' do
    parent = schema['description']['resources']['widget']
    parent['resources']['type'] = {
      'actions' => { 'match' => action(path: '/v1.0/widgets/{widget_id}/types/{type_id}') }, 'resources' => {}
    }
    context.resource_path = %w[widget type]
    context.action_name = 'match'
    context.sample[:path_params] = ['parent / %', "child\\\"\n</script>"]
    expect(render[:code]).to include('api.widget__type_("parent / %").match_(')
    expect(render[:code]).to include('child\\\\\\"\\n</script>')
  end

  it 'keeps blocking construction, execution and destruction in a synchronous main' do
    source = render(:blocking)[:code]
    expect(source).to include('use fixture_client::blocking::Client;', 'features = ["blocking"]',
                              'fn main()', '.send()?')
    expect(source).not_to include('#[tokio::main]', '.await')
  end

  it 'renders failures using actual error diagnostics instead of a success result' do
    context.sample[:status] = false
    expect(render[:code]).to include('match api.', 'error.http_status()', 'error.validation_errors()')
    expect(render[:code]).not_to include('let response =', 'response.output')
  end

  it 'does not render an action omitted from current authorized help' do
    context.description = Marshal.load(Marshal.dump(context.description))
    context.description['resources']['widget']['actions'].clear
    expect(render).to eq(status: :limitation, reason: 'This action is unavailable in the authorized Rust SDK profile.')
    expect(render.inspect).not_to include('name', 'schema', '/v1')
  end

  it 'rejects changed sample fields without exposing hidden saved names or dropping inputs' do
    context.sample[:request][:hidden] = 'secret sample'
    expect(render[:status]).to eq(:limitation)
    expect(render.inspect).not_to include('hidden', 'secret sample')
  end

  it 'rejects stale sample parameter types and routes but permits unrelated live additions' do
    context.description = Marshal.load(Marshal.dump(context.description))
    context.description['resources']['other'] = { 'actions' => {}, 'resources' => {} }
    expect(render[:status]).to eq(:code)
    context.description['resources']['widget']['actions']['update']['input']['parameters']['name']['type'] = 'Integer'
    expect(render[:status]).to eq(:limitation)
    context.description['resources']['widget']['actions']['update']['path'] = '/v1.0/new/{id}'
    expect(render[:status]).to eq(:limitation)
  end

  it 'does not require hidden optional schema fields or leak their defaults' do
    schema['description']['resources']['widget']['actions']['update']['input']['parameters']['private'] = parameter(default: 'hidden-default')
    context.description = Marshal.load(Marshal.dump(context.description))
    context.description['resources']['widget']['actions']['update']['input']['parameters'].delete('private')
    expect(render[:status]).to eq(:code)
    expect(render[:code]).not_to include('private', 'hidden-default')
  end

  it 'escapes hostile Rust and nested Custom literals' do
    schema['description']['resources']['widget']['actions']['update']['input']['parameters']['data'] = parameter('Custom')
    context.sample[:request] = { name: "quotes\"\\\n\u0001</script>ž", data: { 'x' => [false, 0, nil] } }
    source = render[:code]
    expect(source).to include('\\u{1}', '\\n', '</script>ž', 'serde_json::from_str::<serde_json::Value>')
    expect(source).not_to include("\u0001")
  end

  it 'reports GET nested Custom and list input limitations' do
    target = schema['description']['resources']['widget']['actions']['update']
    target['method'] = 'GET'
    target['input']['parameters']['data'] = parameter('Custom')
    context.sample[:request] = { data: { 'nested' => true } }
    expect(render).to include(status: :limitation, reason: 'Rust GET requests do not support nested Custom query values.')
    target['input']['layout'] = 'object_list'
    context.sample[:request] = []
    expect(described_class.new(snapshot: schema, config:).render(kind: :example, context:, mode: :async))
      .to include(status: :limitation, reason: 'Rust GET requests do not support list input.')
  end

  it 'renders only advertised authentication and uses existing token builder APIs' do
    context.description['authentication']['token'] = { 'http_header' => 'X-Token' }
    result = render(:async, :auth, auth_method: :token, auth_description: { http_header: 'X-Token' })
    expect(result[:code]).to include('.token(std::env::var("HAVEAPI_TOKEN")?)')
    expect(render(:async, :auth, auth_method: :oauth2, auth_description: {})[:status]).to eq(:limitation)
  end

  it 'rejects prose-only samples and mismatched selected API versions' do
    context.sample = { title: 'prose only', comment: 'No request', status: true, http_status: 200,
                       path_params: nil, request: nil, response: nil }
    expect(render[:status]).to eq(:limitation)
    context.version = '9'
    expect(render[:status]).to eq(:limitation)
  end

  it 'validates generator config and snapshot during construction' do
    expect { described_class.new(snapshot: schema, config: config.merge('extra' => true)) }
      .to raise_error(HaveAPI::RustClient::Error, /config/)
    expect { described_class.new(snapshot: schema.merge('api_version' => 'invalid'), config:) }
      .to raise_error(HaveAPI::RustClient::Error)
  end

  it 'keeps resolved mappings immutable without freezing caller containers' do
    expect(adapter.resolve(resource_path: ['widget'], action_name: 'update')).to be_frozen
    expect(schema).not_to be_frozen
    expect(config).not_to be_frozen
    expect(render).to be_frozen
    expect(render[:code]).to be_frozen
  end

  it 'rejects unavailable required metadata without inventing payload values' do
    target = schema['description']['resources']['widget']['actions']['update']
    target['meta']['global'] = { 'input' => io('marker' => parameter(required: true)) }
    expect(render[:status]).to eq(:limitation)
    expect(render.inspect).not_to include('marker')
  end

  it 'reports invalid output layout and changed authorized response fields' do
    context.sample[:response] = []
    expect(render[:status]).to eq(:limitation)
    context.sample[:response] = { unknown: true }
    expect(render[:status]).to eq(:limitation)
  end

  %i[async blocking].product(%w[object object_list]).each do |mode, layout|
    context "with #{mode} #{layout} Float input" do
      before do
        schema['description']['resources']['widget']['actions']['update']['input'] = io(
          { 'amount' => parameter('Float') }, layout:
        )
      end

      [10**400, -(10**400), Complex(1, 1)].each_with_index do |value, index|
        it "rejects unsupported numeric value #{index + 1} before literal emission" do
          object = { amount: value }
          context.sample[:request] = layout == 'object_list' ? [object] : object
          expect(render(mode)).to eq(status: :limitation, reason: 'A sample value cannot be represented by this Rust SDK.')
        end
      end

      it 'preserves representable finite integers and floats' do
        [0, -42, 10**100, 1.25, Float::MAX].each do |value|
          object = { amount: value }
          context.sample[:request] = layout == 'object_list' ? [object] : object
          result = render(mode)
          expect(result[:status]).to eq(:code)
          expect(result[:code]).to include("#{value.to_f}_f64")
          expect(result[:code]).not_to include('Infinity_f64', 'NaN_f64')
        end
      end
    end
  end
end
