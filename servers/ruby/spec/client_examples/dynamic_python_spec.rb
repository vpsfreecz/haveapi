require 'spec_helper'
require 'open3'
require_relative 'dynamic_fixture'

RSpec.describe HaveAPI::ClientExamples::PythonClient do
  include DynamicExampleFixture

  let(:renderers) { [described_class, HaveAPI::ClientExamples::PythonAsyncClient] }

  it 'keeps both variants available without a generated SDK profile' do
    expect(renderers.map(&:id)).to eq(%w[python-sync python-async])
    expect(renderers.map(&:order)).to eq([14, 15])
    expect(renderers).to all(be_available(dynamic_context))
  end

  it 'renders complete parseable init, auth, action and async ownership' do
    renderers.each do |renderer|
      context = dynamic_context(detail: :thorough)
      results = [renderer.render(:init, context:), renderer.render(:example, context:)]
      %i[basic token oauth2].each do |method|
        results << renderer.render(:auth, context:, auth_method: method, auth_description: token_description)
      end
      results.each do |result|
        expect(result[:status]).to eq(:code), result.inspect
        expect(result).to be_frozen
        output, status = Open3.capture2e('python', '-c',
                                         'import ast, json, sys; print(json.dumps([type(node).__name__ for node in ast.parse(sys.stdin.read()).body]))',
                                         stdin_data: result[:code])
        expect(status).to be_success, output
        statements = JSON.parse(output)
        expect(result[:code]).not_to include('__main__')
        if renderer.id == 'python-async'
          expect(statements.count('AsyncFunctionDef')).to eq(1)
          expect(statements.last).to eq('Expr')
          expect(result[:code]).to include("\nasyncio.run(main())\n")
        else
          expect(statements).to include('Try')
          expect(statements).not_to include('FunctionDef', 'AsyncFunctionDef')
        end
        expect(result[:code]).to include('https://api.example.test/mount/', 'version="2"')
        expect(result[:code]).to include('except ActionError', 'except HaveAPIError')
      end
    end
  end

  it 'preserves exact mapping names, positional path order and every input value' do
    renderers.each do |renderer|
      source = renderer.render(:example, context: dynamic_context).fetch(:code)
      expect(source).to include('.resources["constructor"].resources["resources"].actions[',
                                'path_params={"parent_id": 7, "widget_id": "name/with space"}',
                                '"enabled": False', '"count": 0', '"nullable": None', '"__proto__":',
                                'print(response.data)')
      if renderer.id == 'python-async'
        expect(source).to include('response = await ', 'async function')
      else
        expect(source).to include('response = api.resources')
        expect(source).not_to include('await ')
      end
    end
  end

  it 'keeps simple setup and authentication parseable with only the imports they use' do
    renderers.each do |renderer|
      init = renderer.render(:init, context: dynamic_context).fetch(:code)
      sources = [init]
      %i[basic token oauth2].each do |method|
        sources << renderer.render(:auth, context: dynamic_context, auth_method: method, auth_description: token_description).fetch(:code)
      end
      sources.each do |source|
        output, status = Open3.capture2e('python', '-c', 'import ast, sys; ast.parse(sys.stdin.read())', stdin_data: source)
        expect(status).to be_success, output
        expect(source).not_to include('__main__', 'except ', 'ActionError', 'HaveAPIError', 'print("Authenticated")')
        if renderer.id == 'python-async'
          expect(source).to include('async def main()', "\nasyncio.run(main())\n")
        else
          expect(source).not_to include('def main', 'asyncio')
        end
      end
      expect(init).not_to include('import os', 'import json')
      basic = sources[1]
      expect(basic).to include('BasicAuth("user", "secret")')
      expect(basic).not_to include('import json')
      expect(sources[2]).to include('begin_token_login', 'continuations', 'step.next_action')
      expect(sources.join).not_to include('import os', 'import json', 'os.environ')
    end
  end

  it 'retains list rows and exposes a limitation for an unnamespaced list' do
    action = dynamic_action.merge(input: { layout: :hash_list, namespace: :widgets, parameters: { name: { type: 'String' } } })
    context = dynamic_context(action:, sample: dynamic_sample.merge(request: [{ name: '' }, { name: 'second' }]))
    renderers.each do |renderer|
      source = renderer.render(:example, context:).fetch(:code)
      expect(source).to include('params=[{"name": ""}, {"name": "second"}]')
      result = renderer.render(:example, context: context.with(action: action.merge(input: action[:input].merge(namespace: nil))))
      expect(result[:status]).to eq(:limitation)
    end
  end

  it 'does not turn a prose-only or incomplete example into an executable call' do
    renderers.each do |renderer|
      [dynamic_sample.merge(path_params: []), { request: nil, response: nil }].each do |sample|
        result = renderer.render(:example, context: dynamic_context(sample:))
        expect(result[:status]).to eq(:limitation)
      end
    end
  end

  it 'uses real token challenge APIs and advertised login fields without printing credentials' do
    renderers.each do |renderer|
      source = renderer.render(:auth, context: dynamic_context, auth_method: :token, auth_description: token_description).fetch(:code)
      expect(source).to include('begin_token_login', 'step.input', 'step.submit(values)', '"login-name": "login-name"')
      expect(source).not_to include('print(step.token)', 'qwertyuiop')
    end
  end

  it 'keeps advertised required lifecycle fields while omitting optional interval in both modes' do
    description = token_description
    parameters = description[:resources][:token][:actions]['request'][:input][:parameters]
    parameters[:lifetime][:required] = true
    parameters[:interval] = { type: 'Integer', required: false }
    renderers.each do |renderer|
      source = renderer.render(:auth, context: dynamic_context, auth_method: :token, auth_description: description).fetch(:code)
      expect(source).to include('"lifetime": "fixed"')
      expect(source).not_to include('HAVEAPI_AUTH_interval', 'HAVEAPI_CHALLENGE_token', 'renewable_auto')
      expect(source).to include('step.next_action', 'step.submit(values)', 'name not in values')
    end
    parameters[:interval][:required] = true
    renderers.each do |renderer|
      source = renderer.render(:auth, context: dynamic_context, auth_method: :token, auth_description: description).fetch(:code)
      expect(source).to include('"interval": 1')
    end
  end

  it 'limits GET examples to flat scalars and safe query names in both modes' do
    action = dynamic_action.merge(method: 'GET', input: {
      layout: :hash, namespace: :widget, parameters: { payload: { type: 'Custom', nullable: true } }
    })
    renderers.each do |renderer|
      [{ enabled: false, count: 0 }, [], {}, { nested: 'string' }, ['string'], false, 0].each do |payload|
        result = renderer.render(:example, context: dynamic_context(action:, sample: dynamic_sample.merge(request: { payload: })))
        expect(result[:status]).to eq(:limitation)
        expect(result[:reason]).to include('flat scalar')
      end
      [nil, '', 'safe'].each do |payload|
        result = renderer.render(:example, context: dynamic_context(action:, sample: dynamic_sample.merge(request: { payload: })))
        expect(result[:status]).to eq(:code), result.inspect
      end
      unsafe = action.merge(input: action[:input].merge(namespace: 'bad[name]'))
      expect(renderer.render(:example, context: dynamic_context(action: unsafe, sample: dynamic_sample.merge(request: {})))[:status]).to eq(:limitation)
    end
  end

  it 'keeps JSON input intact and limits methods unsupported by Python' do
    renderers.each do |renderer|
      %w[POST PUT DELETE HEAD OPTIONS].each do |method|
        result = renderer.render(:example, context: dynamic_context(action: dynamic_action.merge(method:)))
        expect(result[:status]).to eq(%w[POST PUT DELETE].include?(method) ? :code : :limitation)
      end
    end
  end
end
