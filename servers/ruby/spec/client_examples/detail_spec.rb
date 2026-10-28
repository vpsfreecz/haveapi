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
end
