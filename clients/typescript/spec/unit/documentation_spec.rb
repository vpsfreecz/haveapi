require_relative '../documentation/fixtures'
require_relative '../documentation/compilation'

RSpec.describe HaveAPI::TypeScriptClient::Documentation do
  include TypeScriptDocumentationFixtures
  include TypeScriptDocumentationCompilation

  it 'type-checks conventionally spaced imports and prototype-safe values at both details' do
    adapter = documentation_adapter
    snippets = %i[simple thorough].flat_map do |detail|
      context = documentation_context(detail:)
      [adapter.render(kind: :init, context:).fetch(:code),
       adapter.render(kind: :auth, context:, auth_method: :basic).fetch(:code),
       adapter.render(kind: :auth, context:, auth_method: :token).fetch(:code),
       executable_documentation(adapter, context, adapter.render(kind: :example, context:).fetch(:code))]
    end
    expect(snippets.first).to include('import { AsyncClient } from "haveapi-client";', 'import { createClient } from "widget-client";')
    Dir.mktmpdir('haveapi-documentation-style-') do |directory|
      runtime = File.expand_path('../../../js/dist/types/haveapi.d.ts', __dir__)
      stdout, stderr, status = compile_documentation(directory, documentation_snapshot, snippets, runtime_types: runtime)
      expect(status).to be_success, "#{stdout}\n#{stderr}"
    end
  end

  it 'renders simple fragments using the same canonical calls and values without repeated setup' do
    context = documentation_context(detail: :simple)
    adapter = documentation_adapter
    source = adapter.render(kind: :example, context:).fetch(:code)
    expect(source).to include('const result = await api.widget.update', '"cleared": null', '"enabled": false', '"count": 0',
                              '"wire_name": "mapped"', 'console.log(result.data.name)')
    expect(source).not_to include('AsyncClient', 'createClient', 'function main', 'credential(', 'catch', 'result.meta')
    context.detail = :thorough
    expect(adapter.render(kind: :example, context:).fetch(:code)).to include('createClient', 'catch (error)', 'error instanceof AsyncError')
  end

  it 'uses identifier properties and escaped literal access for actual output wire names in both layouts' do
    schema = documentation_snapshot
    fields = { 'class' => parameter, '雪' => parameter, 'wire-name' => parameter,
               'quote"\\<&' => parameter, '7days' => parameter }
    %w[update index].each { |name| schema['description']['resources']['widget']['actions'][name]['output']['parameters'].merge!(fields) }
    adapter = documentation_adapter(schema)
    %w[update index].product(%i[simple thorough]).each do |action_name, detail|
      context = documentation_context(schema, action_name:, detail:)
      row = fields.to_h { |name, _| [name, 'visible value'] }
      context.sample[:response] = action_name == 'index' ? [row] : row
      source = adapter.render(kind: :example, context:).fetch(:code)
      root = action_name == 'index' || detail == :thorough ? 'item' : 'result.data'
      expect(source).to include("#{root}.class", "#{root}.雪", "#{root}[\"wire-name\"]", "#{root}[\"7days\"]")
      quoted_key = '["quote\\"\\\\<&"]'
      expect(source).to include("#{root}#{quoted_key}")
      expect(source).not_to include("#{root}.wire_name")
    end
  end

  it 'preserves normalized canonical names, aliases and prototype-safe input literals' do
    schema = documentation_snapshot
    resources = schema['description']['resources']
    resources['my-widget'] = Marshal.load(Marshal.dump(resources['widget']))
    actions = resources['my-widget']['actions']
    actions['do-work'] = actions.delete('update')
    context = documentation_context(schema)
    context.resource_path = ['my-widget']
    context.action_name = 'change'
    context.action = actions['do-work']
    source = documentation_adapter(schema).render(kind: :example, context:).fetch(:code)
    expect(source).to include('api.my_widget.do_work(', '["__proto__"]: { "kept": true }', '"wire_name": "mapped"')
    expect(source).not_to include('api["my_widget"]', '.change(')
  end

  it 'states only configured package identity without claiming a runtime version' do
    context = documentation_context
    pinned = documentation_adapter
    unversioned = described_class.from_snapshot(snapshot: documentation_snapshot, package_name: 'widget-client')
    expect(pinned.render(kind: :init, context:).fetch(:code)).to start_with('// Configured API client: widget-client@1.2.3.')
    expect(unversioned.render(kind: :init, context:).fetch(:code)).to start_with('// Configured API client: widget-client.')
    [pinned, unversioned].each do |adapter|
      %i[init auth example].each do |kind|
        source = adapter.render(kind:, context:, auth_method: :basic, auth_description: {}).fetch(:code)
        expect(source).not_to include('SDK', 'runtime:', 'haveapi-client@')
        expect(source).to include('from "haveapi-client"', 'from "widget-client"')
      end
    end
  end

  it 'offers Simple initialization and both awaited auth/action diagnostics without a second render' do
    adapter = documentation_adapter
    context = documentation_context(detail: :simple)
    results = %i[init auth example].to_h do |kind|
      [kind, adapter.render(kind:, context:, auth_method: :basic, auth_description: {})]
    end
    context.sample[:status] = false
    results[:failure] = adapter.render(kind: :example, context:)
    context.sample[:request]['count'] = 'invalid'
    results[:limitation] = adapter.render(kind: :example, context:)
    calls = []
    observer = TracePoint.new(:call) do |event|
      calls << event.method_id if event.self.equal?(adapter) && event.method_id == :render
    end
    observer.enable do
      results.each do |kind, result|
        levels = adapter.detail_levels_for(kind: %i[init auth].include?(kind) ? kind : :example,
                                           context:, result:, mode: :async, auth_method: :basic, auth_description: {})
        expect(levels).to eq(%i[auth example failure].include?(kind) ? %i[simple thorough] : [:simple])
        expect(levels).to be_frozen
      end
    end
    expect(calls).to be_empty
    context = documentation_context
    thorough = adapter.render(kind: :example, context:).fetch(:code)
    expect(thorough).to include('catch (error)', 'error instanceof AsyncError', 'const value0: unknown')
    context.sample[:status] = false
    expect(adapter.render(kind: :example, context:).fetch(:code)).to include('error.errors, error.envelope, error.response')
  end

  it 'wraps awaited Basic and token authentication and typed action setup in the known-error handler' do
    schema = documentation_snapshot
    fixture_action(schema)['auth'] = true
    context = documentation_context(schema, detail: :thorough)
    adapter = documentation_adapter(schema)
    %i[basic token].each do |provider|
      source = adapter.render(kind: :auth, context:, auth_method: provider).fetch(:code)
      expect(source).to include('try {', 'error instanceof AsyncError', 'throw error;')
      expect(source.index('try {')).to be < source.index('await runtime.authenticate')
      expect(source).not_to include('credential(', 'node:process', 'HAVEAPI_', 'env[')
    end
    action = adapter.render(kind: :example, context:).fetch(:code)
    expect(action.index('try {')).to be < action.index('await runtime.authenticate')
    expect(action).to include('user: "user", password: "secret"', 'api.widget.update')
    expect(adapter.render(kind: :auth, context:, auth_method: :token).fetch(:code)).to include('token: "example-token"')
  end

  it 'uses the runtime error class for a simple documented rejection and preserves limitations' do
    context = documentation_context(detail: :simple)
    context.sample[:status] = false
    adapter = documentation_adapter
    source = adapter.render(kind: :example, context:).fetch(:code)
    expect(source).to include('import { AsyncError } from "haveapi-client"', 'error instanceof AsyncError', 'error.httpStatus')
    expect(source).not_to include('result.data', 'error.envelope', 'function main')
    context.sample[:request]['count'] = 'invalid'
    before = Marshal.dump(context.sample)
    results = %i[simple thorough].map do |detail|
      context.detail = detail
      adapter.render(kind: :example, context:)
    end
    expect(results.first).to include(status: :limitation)
    expect(results.last).to eq(results.first)
    expect(Marshal.dump(context.sample)).to eq(before)
  end

  it 'copies and freezes the API client model, resolving canonical actions and aliases without allocating names' do
    schema = documentation_snapshot
    adapter = documentation_adapter(schema)
    canonical = adapter.resolve(resource_path: [:widget], action_name: :update)
    expect(adapter.resolve(resource_path: ['widget'], action_name: 'change')).to equal(canonical)
    expect(canonical).to be_frozen
    expect(adapter).to be_frozen
    schema['description']['resources'].clear
    expect(adapter.resolve(resource_path: ['widget'], action_name: 'update')).to equal(canonical)
    expect { canonical[:schema_path].first.replace('wrong') }.to raise_error(FrozenError)
  end

  it 'supports complete mounted descriptions and rejects invalid package or snapshot identity' do
    schema = documentation_snapshot
    adapter = described_class.from_description(description: schema['description'], api_version: '1.0', protocol_version: '2.0', mount_path: '/api/',
                                               package_name: '@widgets/client', package_version: '1.2.3-beta.1+build')
    expect(adapter.render(kind: :init, context: documentation_context)[:code]).to include('"@widgets/client"', 'https://api.example.test/api/v1.0')
    ['../client', '@broken', 'https://example.test/sdk', 'node_modules', 'Widget'].each do |name|
      expect { described_class.from_snapshot(snapshot: schema, package_name: name) }.to raise_error(HaveAPI::TypeScriptClient::Error)
    end
    %w[latest ^1.0.0 01.0.0 1.2.3-01 1.2.3-a.01].each do |version|
      expect { described_class.from_snapshot(snapshot: schema, package_name: 'widget-client', package_version: version) }.to raise_error(HaveAPI::TypeScriptClient::Error)
    end
  end

  it 'renders the canonical public factory, exact mounted version URL, mapped inputs and conservative output guards' do
    adapter = documentation_adapter
    context = documentation_context
    result = adapter.render(kind: :example, context:)
    expect(result[:status]).to eq(:code)
    expect(result[:code]).to include('new AsyncClient("https://api.example.test/api/v1.0")', 'createClient({ execute: spec => runtime.request(spec) })',
                                     'api.widget.update', '"wire_name": "mapped"', '"cleared": null', '"enabled": false', '"count": 0',
                                     'result.data, result.meta, result.envelope, result.httpStatus', 'const value0: unknown')
    expect(result[:code]).not_to include('findResource', 'findAction', 'waitForCompletion', 'runtime.setup', ' as ')
    context.action_name = 'change'
    expect(adapter.render(kind: :example, context:)[:code]).to include('api.widget.update')
  end

  it 'uses only authorized fields, tolerates unrelated additions and does not expose private API client diagnostics' do
    adapter = documentation_adapter
    context = documentation_context
    context.action['output']['parameters'].delete('custom')
    context.sample[:response].delete('custom')
    context.action['input']['parameters']['unrelated'] = parameter
    expect(adapter.render(kind: :example, context:)[:status]).to eq(:code)
    context.sample[:response]['custom'] = 'hidden sample'
    rejected = adapter.render(kind: :example, context:)
    expect(rejected[:status]).to eq(:limitation)
    expect(rejected[:reason]).not_to include('custom', 'hidden', 'widget')
    context.description['resources'].clear
    expect(adapter.render(kind: :example, context:)[:status]).to eq(:limitation)
  end

  it 'limits stale routes, versions, metadata, parameter contracts and missing required values' do
    changes = [
      ->(context) { context.version = '2.0' },
      ->(context) { context.version_url = 'https://user:password@api.example.test/api/v1.0/' },
      ->(context) { context.version_url += '?query=value' },
      ->(context) { context.action['path'] = '/api/v1.0/changed' },
      ->(context) { context.action['method'] = 'POST' },
      ->(context) { context.action['blocking'] = true },
      ->(context) { context.action['input']['namespace'] = 'changed' },
      ->(context) { context.action['input']['parameters']['name']['type'] = 'Integer' },
      ->(context) { context.action['input']['parameters']['name']['nullable'] = true },
      ->(context) { context.description['meta']['namespace'] = 'changed' },
      ->(context) { context.action['meta']['global']['input']['parameters']['notify']['required'] = true },
      ->(context) { context.sample[:request].delete('name') },
      ->(context) { context.action['input']['parameters'].delete('name') },
      ->(context) { context.sample[:path_params] = [9_007_199_254_740_992] },
      ->(context) { context.sample[:path_params] = ['..'] },
      ->(context) { context.sample[:request]['name'] = nil },
      ->(context) { context.sample[:request]['count'] = 1.5 }
    ]
    changes.each do |change|
      results = %i[simple thorough].map do |detail|
        context = documentation_context(detail:)
        change.call(context)
        documentation_adapter.render(kind: :example, context:)
      end
      expect(results.first[:status]).to eq(:limitation)
      expect(results.last).to eq(results.first)
    end
    context = documentation_context(action_name: 'index')
    context.sample[:request]['custom'] = { 'not' => 'a scalar' }
    expect(documentation_adapter.render(kind: :example, context:)[:status]).to eq(:limitation)
  end

  it 'requires runtime-owned advertised Basic or existing-token authentication and renders rejection receipts' do
    schema = documentation_snapshot
    fixture_action(schema)['auth'] = true
    context = documentation_context(schema)
    adapter = documentation_adapter(schema)
    expect(adapter.render(kind: :example, context:)[:code]).to include('runtime.authenticate("basic"')
    context.description['authentication'].delete('basic')
    expect(adapter.render(kind: :example, context:)[:code]).to include('runtime.authenticate("token"', 'token: "example-token"')
    context.description['authentication']['token']['http_header'] = 'Wrong'
    expect(adapter.render(kind: :example, context:)[:status]).to eq(:limitation)
    expect(adapter.render(kind: :auth, context: documentation_context, auth_method: 'oauth2', auth_description: {})[:status]).to eq(:limitation)
    context = documentation_context
    context.sample[:status] = false
    code = documentation_adapter.render(kind: :example, context:)[:code]
    expect(code).to include('error instanceof AsyncError', 'error.envelope, error.response')
    expect(code).not_to include('console.log', 'retry')
  end

  it 'does not traverse unrelated subtrees when rendering an aliased protected example or authentication' do
    schema = documentation_snapshot
    fixture_action(schema)['auth'] = true
    adapter = documentation_adapter(schema)
    context = documentation_context(schema)
    context.action_name = 'change'
    unrelated = { 'private' => 'unrelated body' }
    allow(unrelated).to receive(:to_h).and_call_original
    context.description['resources']['unrelated'] = unrelated
    widget = context.description['resources']['widget']
    widget['resources']['unrelated'] = unrelated
    widget['actions']['unrelated'] = { 'aliases' => ['other'], 'input' => unrelated }
    context.description['authentication']['unrelated'] = unrelated
    context.description['meta']['unrelated'] = unrelated

    expect(adapter.render(kind: :example, context:)[:code]).to include('api.widget.update', 'runtime.authenticate("basic"')
    expect(adapter.render(kind: :auth, context:, auth_method: :token)[:code]).to include('runtime.authenticate("token"')
    expect(unrelated).not_to have_received(:to_h)
  end

  it 'preserves symbol values and last-insertion collisions in mixed request description keys' do
    adapter = documentation_adapter
    [false, true].each do |symbol_last|
      context = documentation_context
      selected = context.description.fetch('resources')
      symbols = JSON.parse(JSON.generate(context.description), symbolize_names: true)
      symbols[:resources][:widget][:actions][:update][:aliases] = [:change]
      symbols[:meta][:namespace] = symbols[:meta][:namespace].to_sym
      context.description = if symbol_last
                              { 'resources' => {}, **symbols }
                            else
                              { resources: {}, **context.description }
                            end
      context.action_name = :change
      expect(adapter.render(kind: :example, context:)[:status]).to eq(:code)
      context.description = symbol_last ? { **symbols, 'resources' => {} } : { 'resources' => selected, resources: {} }
      expect(adapter.render(kind: :example, context:)[:status]).to eq(:limitation)
    end
  end

  it 'prefers canonical actions over aliases and rejects ambiguous aliases without visiting their bodies' do
    adapter = documentation_adapter
    context = documentation_context
    actions = context.description['resources']['widget']['actions']
    actions['other'] = { 'aliases' => %i[update change], 'path' => '/wrong' }
    expect(adapter.render(kind: :example, context:)[:status]).to eq(:code)
    context.action_name = 'change'
    expect(adapter.render(kind: :example, context:)[:status]).to eq(:limitation)
    actions.delete('other')
    actions['update']['aliases'] = [:change]
    expect(adapter.render(kind: :example, context:)[:code]).to include('api.widget.update')
  end

  it 'selects advertised authentication with mixed keys and rejects changed headers and explicit descriptions' do
    context = documentation_context
    adapter = documentation_adapter
    providers = { token: { http_header: 'X-Widget-Token' } }
    context.description = { authentication: providers, **context.description.except('authentication') }
    expect(adapter.render(kind: :auth, context:, auth_method: :token, auth_description: providers[:token])[:status]).to eq(:code)
    expect(adapter.render(kind: :auth, context:, auth_method: :basic)[:status]).to eq(:limitation)
    expect(adapter.render(kind: :auth, context:, auth_method: :token, auth_description: {})[:status]).to eq(:limitation)
    providers[:token]['http_header'] = 'Changed'
    expect(adapter.render(kind: :auth, context:, auth_method: :token)[:status]).to eq(:limitation)
    providers[:token] = { http_header: "X-Widget-Token\n" }
    expect(adapter.render(kind: :auth, context:, auth_method: :token)[:status]).to eq(:limitation)
  end

  it 'does not mutate frozen request inputs or retain authorization decisions between contexts' do
    adapter = documentation_adapter
    allowed = documentation_context
    denied = documentation_context
    denied.description['resources'].clear
    freeze_tree = lambda do |value|
      case value
      when Hash
        value.each do |key, item|
          freeze_tree.call(key)
          freeze_tree.call(item)
        end
      when Array then value.each { |item| freeze_tree.call(item) }
      end
      value.freeze
    end
    [allowed, denied].each do |context|
      context.each { |value| freeze_tree.call(value) }
      context.freeze
    end
    before = Marshal.dump([allowed, denied])
    first = adapter.render(kind: :example, context: allowed)
    expect(first[:status]).to eq(:code)
    expect(adapter.render(kind: :example, context: denied)[:status]).to eq(:limitation)
    expect(adapter.render(kind: :example, context: allowed)).to eq(first)
    expect(Marshal.dump([allowed, denied])).to eq(before)
  end
end
