require 'haveapi/go_client/documentation'
require_relative '../support/documentation_fixture'

RSpec.describe HaveAPI::GoClient::Documentation do
  let(:description) { GoDocumentationFixture.description }
  let(:adapter) { described_class.new(description:, import_path: 'example.test/sdk/client', module_version: 'v1.2.3') }
  let(:action) { description.dig(:resources, :client, :resources, :child, :actions, :client) }
  let(:sample) { GoDocumentationFixture.sample }
  let(:context) do
    Struct.new(:version, :base_url, :description, :resource_path, :action_name, :action, :sample).new(version: '7', base_url: 'https://api.example.test/mounted/', description:,
                                                                                                      resource_path: %w[client child], action_name: 'client', action:, sample:)
  end

  def render
    adapter.render(kind: :example, context:, mode: :sync)
  end

  it 'leaves an omitted module version unresolved and prints the Go latest selector' do
    unversioned = described_class.new(description:, import_path: 'example.test/sdk/client')
    expect(unversioned).to be_frozen
    expect(unversioned.instance_variable_get(:@module_version)).to be_nil
    expect(unversioned.render(kind: :init, context:, mode: :sync).fetch(:code)).to start_with("// go get example.test/sdk/client@latest\n")
    expect(unversioned.render(kind: :example, context:, mode: :sync).fetch(:code)).to eq(
      render.fetch(:code).sub('@v1.2.3', '@latest')
    )
  end

  it 'treats an explicit nil version as omission without changing the canonical model' do
    unversioned = described_class.new(description:, import_path: 'example.test/sdk/client', module_version: nil)
    resolved = unversioned.resolve(resource_path: %w[client child], action_name: 'perform')
    expect(resolved.action.go_member_names).to eq(adapter.resolve(resource_path: %w[client child], action_name: 'perform').action.go_member_names)
    expect(unversioned.render(kind: :example, context:, mode: :sync).fetch(:code)).to include('client "example.test/sdk/client"', 'api.Client.Child.ClientAction.Prepare()')
  end

  it 'still rejects hostile imports when the module version is omitted' do
    expect do
      described_class.new(description:, import_path: "example.test/sdk/client\npackage injected")
    end.to raise_error(ArgumentError, 'invalid Go SDK import path or module version')
  end

  it 'retains explicit version selectors and copies configuration strings' do
    version = +'v2.3.4-rc.1+build.7'
    path = +'example.test/sdk/v2/client'
    pinned = described_class.new(description:, import_path: path, module_version: version)
    version.replace('v9.9.9')
    path.replace('other.test/sdk/client')
    expect(pinned.render(kind: :init, context:, mode: :sync).fetch(:code)).to start_with("// go get example.test/sdk/v2/client@v2.3.4-rc.1+build.7\n")
  end

  ['', 'latest', '1.2.3', "v1.2.3\npackage injected", false, 7].each do |invalid|
    it "rejects a supplied invalid module version #{invalid.inspect}" do
      expect do
        described_class.new(description:, import_path: 'example.test/sdk/client', module_version: invalid)
      end.to raise_error(ArgumentError, 'invalid Go SDK import path or module version')
    end
  end

  it 'resolves canonical generator members and aliases without generator or serving I/O' do
    allow(HaveAPI::GoClient::Generator).to receive(:new).and_call_original
    allow(HaveAPI::GoClient::Generator).to receive(:allocate).and_call_original
    allow(File).to receive(:read).and_call_original
    model = HaveAPI::GoClient::ApiVersion.new(GoDocumentationFixture.description)
    resolved = adapter.resolve(resource_path: %w[client child], action_name: 'perform')
    canonical = model.resources.find { |resource| resource.name == 'client' }.resources.first.actions.first

    expect(resolved.action.go_member_names).to eq(canonical.go_member_names)
    expect(resolved.resource.resource_path.map(&:go_member_name)).to eq(%w[Client Child])
    expect(resolved.action.go_member_name).to eq('ClientAction')
    expect(render[:status]).to eq(:code)
    expect(HaveAPI::GoClient::Generator).not_to have_received(:new)
    expect(HaveAPI::GoClient::Generator).not_to have_received(:allocate)
    expect(File).not_to have_received(:read)
  end

  it 'uses the full saved model even when the visible description has fewer siblings' do
    description[:resources][:set_timeout] = { resources: {}, actions: {} }
    adapter
    context.description = Marshal.load(Marshal.dump(description))
    context.description[:resources].delete(:hidden)
    context.description[:resources].delete(:set_timeout)

    expect(adapter.resolve(resource_path: ['set_timeout'], action_name: 'missing')).to be_nil
    expect(render[:code]).not_to include('hidden', 'secret', 'SetTimeout')
  end

  it 'selects no inputs before supplied setters, preserving null, omission, false and zero' do
    result = render
    expect(result).to be_frozen
    expect(result[:code]).to include('client "example.test/sdk/client"', 'client.New("https://api.example.test")',
                                     'api.Client.Child.ClientAction.Prepare()',
                                     'invocation.SetPathParamInt("client_id", 42)',
                                     'invocation.SetPathParamString("child_id", "a/b")',
                                     'input := invocation.NewInput().SelectParameters()', 'input.SetNameNil(true)',
                                     'input.SetEnabled(false)', 'input.SetCount(0)')
    expect(result[:code]).not_to include('SetUnused')
    expect(result[:code].index('SelectParameters()')).to be < result[:code].index('input.SetNameNil')
  end

  it 'preserves an explicitly empty request and escapes source literals' do
    sample[:request] = {}
    expect(render[:code]).to include('invocation.NewInput().SelectParameters()')
    expect(render[:code]).not_to include('input :=')
    sample[:request] = { name: "quote\"\\\n雪</script>" }
    expect(render[:code]).to include('input.SetName("quote\\"\\\\\\n雪</script>")')
  end

  it 'rejects list input, Custom fields, invalid values, missing paths and stale contracts' do
    sample[:request][:count] = 'wrong'
    expect(render[:status]).to eq(:limitation)
    sample[:request][:count] = 0
    sample[:path_params].pop
    expect(render[:reason]).to include('path parameters')
    sample[:path_params] << 'child'
    action[:input][:parameters][:name][:nullable] = false
    expect(render[:status]).to eq(:limitation)
  end

  it 'reports a list-input limitation rather than discarding fields' do
    action[:input][:layout] = 'hash_list'
    sample[:request] = [{ name: 'a' }]
    expect(render).to include(status: :limitation, reason: /list input/)
  end

  it 'reports unsupported Custom input and output without rendering its contents' do
    action[:input][:parameters][:custom] = { type: 'Custom' }
    sample[:request][:custom] = { secret_value: 'do not render' }
    expect(render).to include(status: :limitation, reason: /Custom/)
    expect(render.to_s).not_to include('secret_value', 'do not render')
  end

  it 'supports list output and refuses scalar null output fidelity claims' do
    action[:output][:layout] = 'hash_list'
    sample[:response] = [{ id: 1 }, { id: 2 }]
    expect(render[:code]).to include('for _, item := range response.Output', 'fmt.Println(item.Id)')
    sample[:response] = [{ name: nil }]
    expect(render).to include(status: :limitation, reason: /scalar null/)
  end

  it 'renders transport errors and API failures separately without invented success output' do
    sample[:status] = false
    sample[:response] = nil
    expect(render[:code]).to include('if err != nil', 'if !response.Status', 'response.Message, response.Errors')
    expect(render[:code]).not_to include('response.Output')
  end

  it 'never exposes a saved action absent from the authorized description' do
    adapter
    context.description = Marshal.load(Marshal.dump(description))
    context.description[:resources].delete(:client)
    expect(render).to include(status: :limitation)
    expect(render.to_s).not_to include('secret', 'hidden')
  end

  it 'checks response schema drift only on fields in the filtered sample' do
    adapter
    context.description = Marshal.load(Marshal.dump(description))
    context.description.dig(:resources, :client, :resources, :child, :actions, :client, :output, :parameters, :id)[:type] = 'String'
    expect(render).to include(status: :limitation, reason: /response field/)
  end

  it 'only renders advertised authentication and uses environment placeholders' do
    basic = adapter.render(kind: :auth, context:, mode: :sync, auth_method: :basic, auth_description: {})
    expect(basic[:code]).to include('api.SetBasicAuthentication(os.Getenv("HAVEAPI_USER"), os.Getenv("HAVEAPI_PASSWORD"))')
    oauth = adapter.render(kind: :auth, context:, mode: :sync, auth_method: :oauth2, auth_description: {})
    expect(oauth[:code]).to include('api.SetExistingOAuth2Auth(os.Getenv("HAVEAPI_ACCESS_TOKEN"))')
    token = adapter.render(kind: :auth, context:, mode: :sync, auth_method: :token, auth_description: {})
    expect(token[:code]).to include('api.SetExistingTokenAuth(os.Getenv("HAVEAPI_TOKEN"))')
    context.description = Marshal.load(Marshal.dump(description))
    context.description[:authentication].delete(:token)
    expect(adapter.render(kind: :auth, context:, mode: :sync, auth_method: :token, auth_description: {})).to include(status: :limitation)
  end

  [[String, String], [Symbol, Symbol], [String, Symbol], [Symbol, String]].each do |saved_type, visible_type|
    it "matches token transport names saved as #{saved_type} and visible as #{visible_type}" do
      description[:authentication][:token].merge!(http_header: saved_type == String ? 'X-Token' : :'X-Token',
                                                  query_parameter: saved_type == String ? 'token' : :token)
      adapter
      context.description = Marshal.load(Marshal.dump(description))
      context.description[:authentication][:token].merge!(http_header: visible_type == String ? 'X-Token' : :'X-Token',
                                                          query_parameter: visible_type == String ? 'token' : :token)

      result = adapter.render(kind: :auth, context:, mode: :sync, auth_method: :token, auth_description: {})
      expect(result[:status]).to eq(:code)
      expect(result[:code]).to include('api.SetExistingTokenAuth(os.Getenv("HAVEAPI_TOKEN"))')
    end
  end

  %i[http_header query_parameter].each do |field|
    it "rejects a different token #{field} even when the other transport matches" do
      adapter
      context.description = Marshal.load(Marshal.dump(description))
      context.description[:authentication][:token][field] = 'other'

      expect(adapter.render(kind: :auth, context:, mode: :sync, auth_method: :token, auth_description: {})).to include(
        status: :limitation, reason: 'This authentication method does not match the configured Go SDK.'
      )
    end

    [nil, false, 7].each do |invalid|
      it "rejects unsupported token #{field} values #{invalid.inspect} without coercion" do
        [[invalid, invalid], [invalid, invalid.to_s], [invalid.to_s, invalid]].each do |saved, visible|
          description[:authentication][:token][field] = saved
          candidate = described_class.new(description:, import_path: 'example.test/sdk/client')
          context.description = Marshal.load(Marshal.dump(description))
          context.description[:authentication][:token][field] = visible

          expect(candidate.render(kind: :auth, context:, mode: :sync, auth_method: :token, auth_description: {})).to include(
            status: :limitation, reason: 'This authentication method does not match the configured Go SDK.'
          )
        end
      end
    end
  end

  %i[saved visible descriptor].each do |missing|
    it "keeps token authentication unavailable without the #{missing} provider description" do
      description[:authentication].delete(:token) if missing == :saved
      adapter
      context.description = Marshal.load(Marshal.dump(description))
      context.description[:authentication][:token] = GoDocumentationFixture.token
      context.description[:authentication].delete(:token) if missing == :visible

      result = adapter.render(kind: :auth, context:, mode: :sync, auth_method: :token,
                              auth_description: missing == :descriptor ? nil : {})
      expect(result).to include(status: :limitation, reason: 'This authentication method is unavailable in the configured Go SDK.')
    end
  end

  it 'does not show operation helpers when action-state visibility is absent' do
    action[:blocking] = true
    action[:meta][:global][:output] = GoDocumentationFixture.io({ action_state_id: { type: 'Integer' } }, namespace: false)
    adapter
    context.description = Marshal.load(Marshal.dump(description))
    context.description[:resources].delete(:action_state)
    expect(render[:code]).not_to include('response.OperationStatus')
    expect(render[:code]).to include('does not establish operation completion')
  end

  it 'uses the origin with mounted versioned SDK paths and rejects a changed mount' do
    expect(render[:code]).to include('client.New("https://api.example.test")')
    expect(adapter.resolve(resource_path: %w[client child], action_name: 'client').action.path).to start_with('/mounted/v7/')
    adapter
    context.description = Marshal.load(Marshal.dump(description))
    context.description.dig(:resources, :client, :resources, :child, :actions, :client)[:path] = '/other/v7/widgets'
    expect(render).to include(status: :limitation, reason: /route/)
  end

  it 'preserves the URL constructor and its authentication and generation options' do
    connection = instance_double(HaveAPI::Client::Communicator, describe_api: description, authenticate: nil)
    allow(HaveAPI::Client::Communicator).to receive(:new).with('https://fixture.invalid').and_return(connection)
    generator = HaveAPI::GoClient::Generator.new('https://fixture.invalid', '/unused',
                                                 version: '7', module: 'example.test/sdk', package: 'client',
                                                 basic_user: 'fixture-user', basic_password: 'fixture-password')
    expect(connection).to have_received(:authenticate).with(:basic, user: 'fixture-user', password: 'fixture-password')
    expect(connection).to have_received(:describe_api).with('7')
    expect(generator.dst).to eq('/unused')
    expect(generator.module).to eq('example.test/sdk')
    expect(generator.package).to eq('client')
  end

  it 'builds a fixture generator from saved input without fetching or writing' do
    allow(HaveAPI::Client::Communicator).to receive(:new).and_call_original
    allow(FileUtils).to receive(:mkpath).and_call_original
    generator = HaveAPI::GoClient::Generator.from_description(description, '/unused', module: 'example.test/sdk', package: 'client')
    expect(generator.dst).to eq('/unused')
    expect(HaveAPI::Client::Communicator).not_to have_received(:new)
    expect(FileUtils).not_to have_received(:mkpath)
  end

  it 'rejects malformed saved schemas at initialization' do
    description[:resources][:client][:resources][:child][:actions][:client][:path] = nil
    expect { adapter }.to raise_error(ArgumentError, /saved Go SDK action/)
  end

  it 'checks Go field and method name collisions' do
    action[:input][:parameters][:select_parameters] = { type: 'String' }
    expect(render).to include(status: :limitation, reason: /name collisions/)
  end

  it 'shows operation methods only for visible matching state actions and metadata' do
    action[:blocking] = true
    action[:meta][:global][:output] = GoDocumentationFixture.io({ action_state_id: { type: 'Integer' } }, namespace: false)
    expect(render[:code]).to include('response.IsBlocking()', 'response.OperationStatus()')
  end

  %i[global object].each do |role|
    [true, false].each do |success|
      it "limits #{role} metadata required in the saved SDK for status #{success}" do
        action[:meta][role] = { input: GoDocumentationFixture.io({ hidden_requirement: { type: 'Boolean', required: true, default: 'private default' } }) }
        sample[:status] = success
        adapter
        context.description = Marshal.load(Marshal.dump(description))
        visible = context.description.dig(:resources, :client, :resources, :child, :actions, :client)
        visible[:meta].delete(role)

        expect(render).to include(status: :limitation, reason: 'This action requires metadata that is absent from the sample.')
        expect(render.to_s).not_to include('hidden_requirement', 'private default', 'SetHiddenRequirement')
      end

      it "limits authorized-live #{role} metadata newly required for status #{success}" do
        adapter
        context.description = Marshal.load(Marshal.dump(description))
        visible = context.description.dig(:resources, :client, :resources, :child, :actions, :client)
        visible[:meta][role] = { input: GoDocumentationFixture.io({ confirm: { type: 'Boolean', required: true } }) }
        sample[:status] = success

        expect(render).to include(status: :limitation, reason: 'This action requires metadata that is absent from the sample.')
        expect(render.to_s).not_to include('confirm', 'SetConfirm')
      end
    end
  end

  it 'preserves optional global guidance and allows optional object metadata without sample values' do
    action[:meta][:global][:input][:parameters][:includes][:required] = false
    action[:meta][:object] = { input: GoDocumentationFixture.io({ confirm: { type: 'Boolean', required: false } }) }
    expect(render[:code]).to include('// metadata := invocation.NewMetaInput().SelectParameters()', '// metadata.SetIncludes(value)')
    expect(render[:code]).not_to include('SetConfirm')
  end

  it 'keeps metadata-free success and failure examples executable' do
    action[:meta] = {}
    expect(render[:status]).to eq(:code)
    expect(render[:code]).not_to include('NewMetaInput')
    sample[:status] = false
    expect(render[:code]).to include('if !response.Status')
  end

  it 'does not disclose hidden global metadata setters' do
    adapter
    context.description = Marshal.load(Marshal.dump(description))
    context.description.dig(:resources, :client, :resources, :child, :actions, :client, :meta, :global, :input, :parameters).clear
    expect(render[:code]).not_to include('NewMetaInput', 'SetIncludes')
  end

  it 'rejects Custom output, invalid path values, and ambiguous aliases safely' do
    action[:output][:parameters][:payload] = { type: 'Custom' }
    sample[:response][:payload] = { private_name: 'private value' }
    expect(render).to include(status: :limitation, reason: /Custom/)
    expect(render.to_s).not_to include('private_name', 'private value')
  end

  it 'keeps alias resolution unambiguous and canonical names preferred' do
    resource = description.dig(:resources, :client, :resources, :child)
    resource[:actions][:other] = GoDocumentationFixture.action(aliases: %w[perform client])
    expect(adapter.resolve(resource_path: %w[client child], action_name: 'perform')).to be_nil
    expect(adapter.resolve(resource_path: %w[client child], action_name: 'client')).not_to be_nil
  end

  it 'preserves partial and nullable Resource output while rejecting scalar association values' do
    action[:output][:parameters][:owner] = { type: 'Resource', resource: ['owner'], value_id: 'id', value_label: 'label', nullable: true }
    sample[:response][:owner] = { id: 9 }
    expect(render[:code]).to include('if response.Output.Owner != nil', 'fmt.Println(response.Output.Owner.Id)')
    expect(render[:code]).not_to include('Owner.Label')
    sample[:response][:owner] = nil
    expect(render[:code]).to include('fmt.Println(response.Output.Owner == nil)')
    sample[:response][:owner] = 9
    expect(render).to include(status: :limitation, reason: /requires an object/)
  end

  it 'matches live Resource identifier symbols against a saved JSON contract' do
    action[:output][:parameters][:owner] = { type: 'Resource', resource: ['owner'], value_id: :id, value_label: :label, nullable: true }
    sample[:response][:owner] = { id: 9 }
    saved = JSON.parse(JSON.generate(description))
    json_adapter = described_class.new(description: saved, import_path: 'example.test/sdk/client', module_version: 'v1.2.3')
    result = json_adapter.render(kind: :example, context:, mode: :sync)

    expect(result[:status]).to eq(:code)
    expect(result[:code]).to include('fmt.Println(response.Output.Owner.Id)')
    expect(result[:code]).not_to include('Owner.Label')
    expect(result[:code]).to eq(render.fetch(:code))
  end

  {
    value_id: ['other', nil, false, 7, [], {}],
    value_label: ['other', nil, false, 7, [], {}],
    type: [:Resource], nullable: [false], resource: [[:owner]]
  }.each do |key, values|
    values.each do |value|
      it "rejects a changed or invalid live Resource contract #{key}: #{value.inspect}" do
        action[:output][:parameters][:owner] = { type: 'Resource', resource: ['owner'], value_id: 'id', value_label: 'label', nullable: true }
        sample[:response][:owner] = { id: 9 }
        adapter
        action[:output][:parameters][:owner][key] = value

        expect(render).to include(status: :limitation, reason: 'This response field does not match the configured Go SDK.')
      end
    end
  end

  it 'does not print associated fields missing from another documented list row' do
    action[:output][:layout] = 'hash_list'
    action[:output][:parameters][:owner] = { type: 'Resource', resource: ['owner'], value_id: 'id', value_label: 'label' }
    sample[:response] = [{ owner: { id: 1, label: 'one' } }, { owner: { id: 2 } }]
    expect(render[:code]).to include('fmt.Println(item.Owner.Id)')
    expect(render[:code]).not_to include('Owner.Label')
  end

  it 'does not guess path argument types or wrap integers' do
    sample[:path_params] = [2**64, 'child']
    expect(render).to include(status: :limitation, reason: /int64 range/)
    sample[:path_params] = [true, 'child']
    expect(render).to include(status: :limitation, reason: /integer or string/)
  end

  it 'rejects malformed profile imports and accepts JSON descriptions' do
    expect do
      described_class.new(description:, import_path: "bad\nsource", module_version: 'v1.0.0')
    end.to raise_error(ArgumentError)
    json_adapter = described_class.new(description: JSON.parse(JSON.generate(description)), import_path: 'example.test/sdk', module_version: 'v1.0.0')
    expect(json_adapter.resolve(resource_path: %w[client child], action_name: 'client')).not_to be_nil
  end
end
