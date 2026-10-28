require 'spec_helper'
require 'open3'
require_relative 'dynamic_fixture'

RSpec.describe HaveAPI::ClientExample, '.render' do
  include DynamicExampleFixture

  let(:renderers) do
    [HaveAPI::ClientExamples::JsClient, HaveAPI::ClientExamples::JsAsyncClient,
     HaveAPI::ClientExamples::TsClient, HaveAPI::ClientExamples::TsAsyncClient,
     HaveAPI::ClientExamples::PythonClient, HaveAPI::ClientExamples::PythonAsyncClient]
  end

  it 'keeps simple actions focused on the existing api and leaves setup and diagnostics to thorough' do
    renderers.each do |renderer|
      context = dynamic_context
      simple = renderer.render(:example, context:).fetch(:code)
      thorough = renderer.render(:example, context: context.with(detail: :thorough)).fetch(:code)
      expect(simple).to include('api', 'name/with space')
      expect(simple).not_to include('import ', 'credential(', 'os.environ', 'new AsyncClient', 'new CallbackClient',
                                    'with Client(', 'with AsyncClient(', 'try:', 'try {', 'response.meta', 'reply.meta()')
      expect(thorough).to include('import ', context.base_url)
      expect(thorough).to include(renderer.code == :python ? 'except HaveAPIError' : 'catch (error)')
      expect(context.detail).to eq(:simple)
      expect(context.sample[:request][:enabled]).to be(false)
      expect(context.sample[:request][:count]).to eq(0)
      expect(context.sample[:request][:nullable]).to be_nil
    end
  end

  it 'returns identical limitations at both levels without revealing hidden sample or metadata values' do
    contexts = [
      dynamic_context(sample: dynamic_sample.merge(path_params: [7])),
      dynamic_context(sample: dynamic_sample.merge(request: { hidden_parameter: 'private-sample' })),
      dynamic_context(sample: { request: nil, response: nil }),
      dynamic_context(action: dynamic_action.merge(meta: {
        global: { input: { parameters: { secret: { required: true, default: 'private-default' } } } }
      }))
    ]
    renderers.each do |renderer|
      contexts.each do |context|
        simple = renderer.render(:example, context:)
        thorough = renderer.render(:example, context: context.with(detail: :thorough))
        expect(simple).to eq(thorough)
        expect(simple[:status]).to eq(:limitation)
        expect(simple[:reason]).not_to include('private-sample', 'private-default', 'hidden_parameter')
      end
    end
  end

  it 'validates unsupported required authentication before returning either action fragment' do
    context = dynamic_context(action: dynamic_action.merge(auth: true), description: { authentication: {} })
    renderers.each do |renderer|
      results = %i[simple thorough].map { |detail| renderer.render(:example, context: context.with(detail:)) }
      expect(results[0]).to eq(results[1])
      expect(results[0][:status]).to eq(:limitation)
    end
  end

  it 'keeps Python async fragments in an explicit async context without adding executable wrappers' do
    source = HaveAPI::ClientExamples::PythonAsyncClient.render(:example, context: dynamic_context).fetch(:code)
    script = 'import ast, sys; ast.parse("async def example():\n" + "".join("    " + line for line in sys.stdin))'
    output, status = Open3.capture2e('python', '-c', script, stdin_data: source)
    expect(status).to be_success, output
    expect(source).to include('# Run inside an async function after initializing api.', 'response = await api.resources')
    expect(source).not_to include('__main__', 'async def ', 'asyncio.run')
  end

  it 'preserves operation waiting and its timeout meaning at both detail levels' do
    context = dynamic_context(action: dynamic_action.merge(blocking: true))
    [HaveAPI::ClientExamples::PythonClient, HaveAPI::ClientExamples::PythonAsyncClient].each do |renderer|
      %i[simple thorough].each do |detail|
        source = renderer.render(:example, context: context.with(detail:)).fetch(:code)
        expect(source).to include('response.operation.wait(timeout=300, interval=1)', 'does not cancel a server operation')
      end
    end
  end

  it 'uses simple fragments for positional dynamic, Ruby and PHP renderers without changing their calls' do
    context = dynamic_context
    args = [context.host, context.base_url, context.version, context.resource_path, context.resource,
            context.action_name, context.action]
    renderers.each do |renderer|
      expect(renderer.new(*args).example(context.sample)).to eq(renderer.render(:example, context:))
    end
    sample = { path_params: [7], request: { name: '' }, status: false }
    action = { output: { layout: :hash } }
    ruby = HaveAPI::ClientExamples::RubyClient.new('api.test', 'https://api.test/', '1', ['widget'], {}, 'show', action)
    php = HaveAPI::ClientExamples::PhpClient.new('api.test', 'https://api.test/', '1', ['widget'], {}, 'show', action)
    expect(ruby.example(sample)).to start_with('reply = api.widget.show(7,')
    expect(php.example(sample)).to start_with('$reply = $api->widget->show(7,')
    expect(ruby.example(sample)).not_to include('HaveAPI::Client.new')
    expect(php.example(sample)).not_to include('new \\HaveAPI\\Client')
  end

  it 'offers callback setup once while preserving real action lookup and reply error handling' do
    [HaveAPI::ClientExamples::JsClient, HaveAPI::ClientExamples::TsClient].each do |renderer|
      context = dynamic_context
      %i[init auth].each do |kind|
        result = renderer.render(kind, context:, auth_method: :basic, auth_description: {})
        expect(result.fetch(:code)).to include('if (!ready)', 'Discovery or authentication failed')
        levels = renderer.detail_levels_for(kind, context:, result:, auth_method: :basic, auth_description: {})
        expect(levels).to eq([:simple])
        expect(levels).to be_frozen
      end
      result = renderer.render(:example, context:)
      expect(result.fetch(:code)).to include('findAction', 'if (!reply.isOk())')
      thorough = renderer.render(:example, context: context.with(detail: :thorough)).fetch(:code)
      expect(thorough).to include('try {', 'catch (error)', 'reply.meta()')
      expect(renderer.detail_levels_for(:example, context:, result:)).to eq(%i[simple thorough])
    end
  end

  it 'offers async discovery and Python context-manager error handling for setup and actions' do
    [HaveAPI::ClientExamples::JsAsyncClient, HaveAPI::ClientExamples::TsAsyncClient,
     HaveAPI::ClientExamples::PythonClient, HaveAPI::ClientExamples::PythonAsyncClient].each do |renderer|
      context = dynamic_context
      %i[init auth example].each do |kind|
        result = renderer.render(kind, context:, auth_method: :basic, auth_description: {})
        levels = renderer.detail_levels_for(kind, context:, result:, auth_method: :basic, auth_description: {})
        expect(levels).to eq(%i[simple thorough])
        expect(levels).to be_frozen
        thorough = renderer.render(kind, context: context.with(detail: :thorough),
                                         auth_method: :basic, auth_description: {}).fetch(:code)
        expect(thorough).to include(renderer.code == :python ? 'except HaveAPIError' : 'error instanceof AsyncError')
      end
    end
  end

  it 'offers Ruby and PHP real error handling while retaining simple direct calls' do
    context = dynamic_context(resource_path: ['widget'], action_name: 'show')
    [HaveAPI::ClientExamples::RubyClient, HaveAPI::ClientExamples::PhpClient].each do |renderer|
      %i[init auth example].each do |kind|
        result = renderer.render(kind, context:, auth_method: :basic, auth_description: {})
        expect(renderer.detail_levels_for(kind, context:, result:, auth_method: :basic)).to eq(%i[simple thorough])
        source = renderer.render(kind, context: context.with(detail: :thorough),
                                       auth_method: :basic, auth_description: {}).fetch(:code)
        expect(source).to include(renderer.code == :ruby ? 'api.setup' : '$api->setup()')
        expect(source).to include('ValidationError', 'ActionFailed', renderer.code == :ruby ? 'rescue' : 'catch')
      end
      expect(context.detail).to eq(:simple)
      expect(context.sample).to eq(dynamic_sample)
    end
  end

  it 'advertises only Simple for built-in limitations without probing another render' do
    context = dynamic_context(sample: dynamic_sample.merge(path_params: [7]))
    results = renderers.to_h { |renderer| [renderer, renderer.render(:example, context:)] }
    renderers.each do |renderer|
      result = results.fetch(renderer)
      expect(result).to include(status: :limitation)
      allow(renderer).to receive(:render).and_call_original
      expect(renderer.detail_levels_for(:example, context:, result:)).to eq([:simple])
      expect(renderer).not_to have_received(:render)
    end
    [HaveAPI::ClientExamples::RubyClient, HaveAPI::ClientExamples::RubyCli].each do |renderer|
      result = renderer.render(:auth, context:, auth_method: :oauth2, auth_description: {})
      expect(result.fetch(:code)).to include('not supported')
      expect(renderer.detail_levels_for(:auth, context:, result:, auth_method: :oauth2,
                                               auth_description: {})).to eq([:simple])
    end
  end

  it 'authenticates protected Ruby and PHP programs with advertised literal existing credentials' do
    context = dynamic_context(action: dynamic_action.merge(auth: true), resource_path: ['widget'], action_name: 'show', detail: :thorough)
    [HaveAPI::ClientExamples::RubyClient, HaveAPI::ClientExamples::PhpClient].each do |renderer|
      result = renderer.render(:example, context:)
      expect(result[:status]).to eq(:code)
      expect(result[:code]).to include('example-token')
      expect(result[:code].index('example-token')).to be < result[:code].index(renderer.code == :ruby ? 'reply = api.widget' : '$reply = $api->widget')
      unsupported = renderer.render(:example, context: context.with(description: { authentication: {} }))
      expect(unsupported).to include(status: :limitation)
    end
  end
end
