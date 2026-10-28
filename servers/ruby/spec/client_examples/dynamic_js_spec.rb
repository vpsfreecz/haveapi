require 'spec_helper'
require 'open3'
require 'tempfile'
require_relative 'dynamic_fixture'

RSpec.describe HaveAPI::ClientExamples::JsClient do
  include DynamicExampleFixture

  let(:renderers) do
    [described_class, HaveAPI::ClientExamples::JsAsyncClient,
     HaveAPI::ClientExamples::TsClient, HaveAPI::ClientExamples::TsAsyncClient]
  end

  def syntax(renderer, source)
    if renderer.code == :typescript
      compiler = File.expand_path('../../../../clients/js/node_modules/typescript', __dir__)
      script = <<~'JS'
        const ts = require(process.argv[1]);
        const source = require('fs').readFileSync(0, 'utf8');
        const result = ts.transpileModule(source, {reportDiagnostics: true, compilerOptions: {target: ts.ScriptTarget.ES2020}});
        for (const diagnostic of result.diagnostics || []) console.error(ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'));
        process.exit((result.diagnostics || []).length ? 1 : 0);
      JS
      Open3.capture2e('node', '-e', script, compiler, stdin_data: source)
    else
      Tempfile.create(['haveapi-doc-js-', '.mjs']) do |file|
        file.write(source)
        file.flush
        Open3.capture2e('node', '--check', file.path)
      end
    end
  end

  it 'keeps all four stable dynamic variants available without profiles' do
    expect(renderers.map(&:id)).to eq(%w[javascript-callback javascript-async typescript-callback typescript-async])
    expect(renderers.map(&:order)).to eq([10, 11, 12, 13])
    expect(renderers).to all(be_available(dynamic_context))
  end

  it 'renders complete syntax-valid initialization, authentication and hostile action programs' do
    renderers.each do |renderer|
      context = dynamic_context(detail: :thorough)
      results = [renderer.render(:init, context:), renderer.render(:example, context:)]
      %i[basic token oauth2].each do |method|
        results << renderer.render(:auth, context:, auth_method: method, auth_description: token_description)
      end
      results.each do |result|
        expect(result[:status]).to eq(:code), result.inspect
        expect(result).to be_frozen
        expect(result[:code]).to include('https://api.example.test/mount/', 'version: "2"')
        output, status = syntax(renderer, result[:code])
        expect(status).to be_success, output
        expect(result[:code]).not_to match(/\bas any\b|\bas unknown\b|\._private|api\.constructor/)
      end
    end
  end

  it 'uses exact public lookups and retains false, zero, null and hostile Custom keys' do
    renderers.each do |renderer|
      source = renderer.render(:example, context: dynamic_context).fetch(:code)
      expect(source).to include('["enabled"]: false', '["count"]: 0', '["nullable"]: null', '["__proto__"]:')
      expect(source).to include('new\\"\\n</script>')
      if renderer.id.end_with?('-async')
        expect(source).to include('.resource("constructor").resource("resources").action(', 'result.value')
      else
        expect(source).to include('CallbackClient.findResource', 'CallbackClient.findAction', 'action.directInvoke', 'reply.message()', 'reply.envelope.errors')
      end
    end
  end

  it 'checks TypeScript examples against the real emitted public declarations with strict types' do
    root = File.expand_path('../../../..', __dir__)
    Dir.mktmpdir('haveapi-ts-docs-') do |directory|
      files = []
      [HaveAPI::ClientExamples::TsClient, HaveAPI::ClientExamples::TsAsyncClient].each_with_index do |renderer, index|
        %i[simple thorough].each do |detail|
          context = dynamic_context(detail:)
          results = [renderer.render(:init, context:), renderer.render(:example, context:)]
          %i[basic token oauth2].each do |method|
            results << renderer.render(:auth, context:, auth_method: method, auth_description: token_description)
          end
          results.each_with_index do |result, number|
            source = result.fetch(:code)
            if detail == :simple && number == 1
              client = renderer.id.end_with?('-async') ? 'AsyncClient' : 'CallbackClient'
              source = "import { #{client} } from \"haveapi-client\";\ndeclare const api: #{client};\n#{source}"
            end
            path = File.join(directory, "#{index}-#{detail}-#{number}.ts")
            File.write(path, source)
            files << path
          end
        end
      end
      options = { strict: true, noEmit: true, target: 'ES2020', module: 'ESNext', moduleResolution: 'node',
                  ignoreDeprecations: '6.0',
                  typeRoots: [File.join(root, 'clients/js/node_modules/@types')], types: ['node'],
                  baseUrl: directory, paths: { 'haveapi-client' => [File.join(root, 'clients/js/dist/types/haveapi')] } }
      config = File.join(directory, 'tsconfig.json')
      File.write(config, JSON.generate({ compilerOptions: options, files: }))
      output, status = Open3.capture2e('node', File.join(root, 'clients/js/node_modules/typescript/bin/tsc'), '-p', config)
      expect(status).to be_success, output
    end
  end

  it 'never drops list input, unknown fields or unresolved path arguments' do
    invalid = [
      dynamic_context(sample: dynamic_sample.merge(request: [{ name: 'row' }])),
      dynamic_context(sample: dynamic_sample.merge(request: { hidden: 'not visible' })),
      dynamic_context(sample: dynamic_sample.merge(path_params: [7])),
      dynamic_context(sample: dynamic_sample.merge(request: { count: 9_007_199_254_740_992 })),
      dynamic_context(sample: { request: nil, response: nil, comment: 'prose only' })
    ]
    renderers.each do |renderer|
      invalid.each do |context|
        result = renderer.render(:example, context:)
        expect(result[:status]).to eq(:limitation)
        expect(result[:reason]).not_to be_empty
        expect(result).not_to have_key(:code)
      end
    end
  end

  it 'limits unsupported or unadvertised authentication instead of inventing a flow' do
    renderers.each do |renderer|
      result = renderer.render(:auth, context: dynamic_context(description: { authentication: {} }), auth_method: :basic, auth_description: {})
      expect(result[:status]).to eq(:limitation)
      result = renderer.render(:auth, context: dynamic_context, auth_method: :custom, auth_description: {})
      expect(result[:status]).to eq(:limitation)
    end
  end

  it 'uses actual operation completion support only for the async client' do
    renderers.each do |renderer|
      source = renderer.render(:example, context: dynamic_context(action: dynamic_action.merge(blocking: true))).fetch(:code)
      if renderer.id.end_with?('-async')
        expect(source).to include('await api.waitForCompletion(result, {timeoutMs: 300000})')
      else
        expect(source).not_to include('waitForCompletion(')
        expect(source).to include('initial response')
      end
    end
  end

  it 'limits nested GET and OPTIONS query input while preserving scalar queries and HEAD bodies' do
    renderers.each do |renderer|
      %w[GET OPTIONS HEAD].each do |method|
        action = dynamic_action.merge(method:)
        result = renderer.render(:example, context: dynamic_context(action:))
        expect(result[:status]).to eq(method == 'HEAD' ? :code : :limitation)
        params = { name: '', enabled: false, count: 0, nullable: nil }
        scalar = renderer.render(:example, context: dynamic_context(action:, sample: dynamic_sample.merge(request: params)))
        expect(scalar[:status]).to eq(:code), scalar.inspect
        expect(scalar[:code]).to include('["enabled"]: false', '["count"]: 0', '["nullable"]: null')
      end
    end
  end

  it 'cross-checks query loss and HEAD bodies against both native JavaScript clients' do
    helper = File.expand_path('../../../../clients/js/test/helpers/async_bundle.cjs', __dir__)
    script = <<~JS
      const assert = require('node:assert/strict');
      const {harness, action, description} = require(process.argv[1]);
      async function check() {
        for (const method of ['GET', 'OPTIONS', 'HEAD']) {
          for (const params of [{payload: {enabled: false, count: 0}}, {enabled: false, count: 0, nullable: null}]) {
            const {HaveAPI, requests} = harness();
            const callback = new HaveAPI.CallbackClient('https://api.example.test');
            const model = description();
            model.resources.widgets.actions.validate = action({payload: {type: 'Custom'}, enabled: {type: 'Boolean'},
              count: {type: 'Integer'}, nullable: {type: 'String', nullable: true}}, {method});
            callback.setup((api, ready) => {
              assert.equal(ready, true);
              const resource = HaveAPI.CallbackClient.findResource(api, ['widgets']);
              HaveAPI.CallbackClient.findAction(resource, 'validate').directInvoke({params});
            });
            requests[0].respond({status: true, version: '2.0', response: model});
            const asyncClient = new HaveAPI.AsyncClient('https://api.example.test');
            const pending = asyncClient.request({method, path: '/v1/validate', inputNamespace: 'widget', params});
            assert.equal(callback.sendAsQueryParams(method), method !== 'HEAD');
            for (const wire of requests.slice(1)) {
              if (method === 'HEAD') {
                assert.deepEqual(JSON.parse(wire.body), {widget: params});
                assert.equal(new URL(wire.url).search, '');
              } else {
                const query = new URL(wire.url).searchParams;
                assert.equal(wire.body, undefined);
                if (params.payload) assert.equal(query.get('widget[payload]'), '[object Object]');
                else {
                  assert.equal(query.get('widget[enabled]'), 'false');
                  assert.equal(query.get('widget[count]'), '0');
                  assert.equal(query.get('widget[nullable]'), '');
                }
              }
              wire.respond({status: true, response: {}});
            }
            await pending;
          }
        }
      }
      check().catch(error => { console.error(error); process.exitCode = 1; });
    JS
    output, status = Open3.capture2e('node', '-e', script, helper)
    expect(status).to be_success, output
  end
end
