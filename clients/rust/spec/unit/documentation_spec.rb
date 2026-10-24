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

  def keyed(value, depth = 0, mixed: false)
    case value
    when Hash
      value.to_h do |key, item|
        [mixed && depth.odd? ? key.to_s : key.to_sym, keyed(item, depth + 1, mixed:)]
      end
    when Array then value.map { |item| keyed(item, depth + 1, mixed:) }
    else value
    end
  end

  %i[async blocking].each do |mode|
    it "preserves #{mode} output with symbol and mixed authorized keys" do
      schema['description']['authentication']['token'] = { 'http_header' => 'X-Token' }
      expected = render(mode)
      original = context.description
      [false, true].each do |mixed|
        context.description = keyed(original, mixed:)
        expect(render(mode)).to eq(expected)
        context.description[:authentication] = { token: { http_header: :'X-Token' } }
        expect(render(mode)[:code]).to include('.token(')
      end
    end

    [true, false].each do |symbol_last|
      it "uses last-inserted colliding keys at every #{mode} lookup level (symbol last: #{symbol_last})" do
        expected = render(mode)
        target = context.description['resources']['widget']['actions']['update']
        collision = lambda do |name, value|
          entries = [[name.to_s, nil], [name.to_sym, value]]
          entries.reverse! unless symbol_last
          entries[0][1] = nil
          entries[1][1] = value
          entries.to_h
        end
        resource = collision.call('actions', collision.call('update', target))
        resource.merge!(collision.call('resources', {}))
        context.description = collision.call('resources', collision.call('widget', resource))
        context.description.merge!(collision.call('authentication', collision.call('basic', {})))
        expect(render(mode)).to eq(expected)

        actions = resource.values.find { |value| value.is_a?(Hash) && value.values.include?(target) }
        actions[actions.keys.last] = nil
        expect(render(mode)[:status]).to eq(:limitation)
      end
    end
  end

  it 'checks the entire advertised provider description and sees changes on every render' do
    schema['description']['authentication']['token'] = { 'http_header' => 'X-Token' }
    context.description = Marshal.load(Marshal.dump(schema['description']))
    context.description['authentication']['token']['resources'] = { 'login' => { 'description' => 'visible' } }
    supplied = keyed(context.description['authentication']['token'])
    adapter.freeze
    expect(render(:async, :auth, auth_method: :token, auth_description: supplied)[:status]).to eq(:code)
    supplied[:resources][:login][:description] = 'different'
    expect(render(:async, :auth, auth_method: :token, auth_description: supplied))
      .to include(status: :limitation, reason: 'The authentication description differs from the authorized help.')
    supplied[:resources][:login][:description] = 'visible'
    context.description['authentication']['token']['http_header'] = 'X-Other'
    supplied[:http_header] = 'X-Other'
    expect(render(:blocking, :auth, auth_method: :token, auth_description: supplied))
      .to include(status: :limitation, reason: 'The Rust SDK authentication header differs from this API.')
    context.description['authentication'].delete('token')
    expect(render(:async, :auth, auth_method: :token, auth_description: supplied)[:status]).to eq(:limitation)
  end

  [true, false].each do |symbol_last|
    it "preserves provider/header collision order (symbol last: #{symbol_last})" do
      schema['description']['authentication']['token'] = { 'http_header' => 'X-Token' }
      context.description = Marshal.load(Marshal.dump(schema['description']))
      context.description['authentication'].delete('basic')
      entries = [%w[http_header wrong], %i[http_header X-Token]]
      entries.reverse! unless symbol_last
      entries[0][1] = 'wrong'
      entries[1][1] = :'X-Token'
      provider = entries.to_h
      providers = [['token', nil], [:token, provider]]
      providers.reverse! unless symbol_last
      providers[0][1] = nil
      providers[1][1] = provider
      context.description['authentication'] = providers.to_h
      expect(render[:code]).to include('.token(')
      expect(render(:async, :auth, auth_method: :token, auth_description: { http_header: 'X-Token' })[:status]).to eq(:code)
      provider[provider.keys.last] = 'wrong'
      expect(render[:status]).to eq(:limitation)
    end
  end

  it 'preserves basic key presence, token/oauth2 preference and public action behavior' do
    auth = schema['description']['authentication']
    auth['token'] = { 'http_header' => 'X-Token' }
    auth['oauth2'] = { 'http_header' => 'Authorization' }
    context.description = Marshal.load(Marshal.dump(schema['description']))
    live = context.description['authentication']
    live['basic'] = nil
    expect(render[:code]).to include('.basic_auth(')
    live['basic'] = false
    expect(render[:code]).to include('.basic_auth(')
    live.delete('basic')
    expect(render[:code]).to include('.token(')
    live['token']['http_header'] = 'wrong'
    expect(render[:code]).to include('.oauth2_token(')
    live.delete('oauth2')
    expect(render[:status]).to eq(:limitation)
    schema['description']['resources']['widget']['actions']['update']['auth'] = false
    context.description['resources']['widget']['actions']['update']['auth'] = false
    context.description['authentication'] = nil
    public_adapter = described_class.new(snapshot: schema, config:)
    expect(public_adapter.render(kind: :example, context:, mode: :async)[:status]).to eq(:code)
  end

  it 'does not retain privileged descriptions, hidden samples or mutable duck-context decisions' do
    target = schema['description']['resources']['widget']['actions']['update']
    target['input']['parameters']['private'] = parameter(default: 'private-default')
    admin = context_type.new(**context.to_h, description: Marshal.load(Marshal.dump(schema['description'])))
    admin.sample = { path_params: [1], request: { private: 'private-value' }, status: true }
    member = context_type.new(**context.to_h, description: Marshal.load(Marshal.dump(schema['description'])))
    member.description['resources']['widget']['actions']['update']['input']['parameters'].delete('private')
    adapter.freeze
    %i[async blocking].each do |mode|
      admin_result = adapter.render(kind: :example, context: admin, mode:)
      expect(admin_result[:code]).to include('private-value')
      member_result = adapter.render(kind: :example, context: member, mode:)
      expect(member_result[:status]).to eq(:code)
      expect(member_result.inspect).not_to include('private', 'private-value', 'private-default')
      expect(adapter.render(kind: :example, context: admin, mode:)).to eq(admin_result)
      member.sample[:request][:name] = 'fresh-member-value'
      expect(adapter.render(kind: :example, context: member, mode:)[:code]).to include('fresh-member-value')
      member.description['resources']['widget']['actions']['update']['input']['parameters']['name']['type'] = 'Integer'
      expect(adapter.render(kind: :example, context: member, mode:)[:status]).to eq(:limitation)
      member.description['resources']['widget']['actions']['update']['input']['parameters']['name']['type'] = 'String'
      member.description['resources']['widget']['actions'].clear
      expect(adapter.render(kind: :example, context: member, mode:)[:status]).to eq(:limitation)
      member.description = Marshal.load(Marshal.dump(context.description))
      member.description['resources']['widget']['actions']['update']['input']['parameters'].delete('private')
    end
  end

  it 'does not authorize malformed selected resource, action or provider shapes' do
    context.description = { 'resources' => { 'widget' => [] }, 'authentication' => { 'basic' => [] } }
    expect(render[:status]).to eq(:limitation)
    expect(render(:async, :auth, auth_method: :basic, auth_description: [])[:status]).to eq(:limitation)
    context.description['resources']['widget'] = { 'actions' => { 'update' => 'invalid' } }
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
