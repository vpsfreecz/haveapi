require 'spec_helper'
require 'open3'
require_relative '../spec/client_examples/dynamic_fixture'

RSpec.describe HaveAPI::ClientExamples::PythonClient do
  include DynamicExampleFixture

  let(:renderers) { [described_class, HaveAPI::ClientExamples::PythonAsyncClient] }

  def python_request(action, params)
    root = File.expand_path('../../..', __dir__)
    source = <<~PY
      import json
      import sys
      from haveapi_client import HaveAPIError
      from haveapi_client._protocol import CallContext, build_request, lookup_action, parse_description

      fixture = json.load(sys.stdin)
      try:
          description = parse_description({
              "status": True, "version": "2.0",
              "response": {"resources": {"widget": {"actions": {"show": fixture["action"]}}}}
          })
          action = lookup_action(description, ("widget",), "show")
          context = CallContext(action, (), dict(zip(action.path_parameters, fixture["path_params"])), 1)
          result = build_request(description, context, base_url="https://api.example.test/", params=fixture["params"])
          print(json.dumps({"query": result.query, "body": json.loads(result.content) if result.content else None}))
      except HaveAPIError as error:
          print(json.dumps({"error": type(error).__name__, "message": str(error)}))
    PY
    output, status = Open3.capture2e(
      { 'PYTHONPATH' => File.join(root, 'clients/python/src'), 'PYTHONDONTWRITEBYTECODE' => '1' },
      File.join(root, 'clients/python/.venv/bin/python'), '-c', source,
      stdin_data: JSON.generate({ action:, params:, path_params: dynamic_sample[:path_params] })
    )
    expect(status).to be_success, output
    JSON.parse(output)
  end

  it 'limits GET Custom structures rejected by the real Python request builder in both modes' do
    action = dynamic_action.merge(method: 'GET', input: {
      layout: :hash, namespace: :widget, parameters: { payload: { type: 'Custom' } }
    })
    [{ enabled: false, count: 0 }, [], {}, { nested: [] }, [{ a: 'one' }, { b: 'two' }], false, 0].each do |value|
      sample = dynamic_sample.merge(request: { payload: value })
      expect(python_request(action, sample[:request])).to include('error' => 'ValidationError')
      renderers.each do |renderer|
        result = renderer.render(:example, context: dynamic_context(action:, sample:))
        expect(result[:status]).to eq(:limitation)
        expect(result[:reason]).to include('Python GET', 'flat scalar')
      end
    end
  end

  it 'preserves flat GET scalars and nullable Custom values supported by the real builder' do
    action = dynamic_action.merge(method: 'GET', input: {
      layout: :hash, namespace: :widget,
      parameters: { name: { type: 'String' }, enabled: { type: 'Boolean' }, count: { type: 'Integer' },
                    nullable: { type: 'String', nullable: true }, payload: { type: 'Custom', nullable: true } }
    })
    [nil, ''].each do |payload|
      params = { name: 'a&ž', enabled: false, count: 0, nullable: nil, payload: }
      expect(python_request(action, params)).to include('query' => [
                                                          ['widget[name]', 'a&ž'], ['widget[enabled]', 'false'], ['widget[count]', '0'],
                                                          ['widget[nullable]', ''], ['widget[payload]', '']
                                                        ])
      renderers.each do |renderer|
        result = renderer.render(:example, context: dynamic_context(action:, sample: dynamic_sample.merge(request: params)))
        expect(result[:status]).to eq(:code), result.inspect
        expect(result[:code]).to include('"enabled": False', '"count": 0', '"nullable": None')
      end
    end
  end

  it 'documents a conservative GET subset and rejects ambiguous query key components' do
    cases = [
      [{ payload: { nested: 'supported by client' } }, :widget, { payload: { type: 'Custom' } }, false],
      [{ payload: ['supported by client'] }, :widget, { payload: { type: 'Custom' } }, false],
      [{ payload: 'text' }, 'bad[name]', { payload: { type: 'String' } }, true],
      [{ 'bad[name]' => 'text' }, :widget, { 'bad[name]' => { type: 'String' } }, true],
      [{ '' => 'text' }, :widget, { '' => { type: 'String' } }, true]
    ]
    cases.each do |params, namespace, parameters, rejected|
      action = dynamic_action.merge(method: 'GET', input: { layout: :hash, namespace:, parameters: })
      expect(python_request(action, params).has_key?('error')).to eq(rejected)
      renderers.each do |renderer|
        expect(renderer.render(:example, context: dynamic_context(action:, sample: dynamic_sample.merge(request: params)))[:status]).to eq(:limitation)
      end
    end
  end

  it 'leaves JSON methods intact and limits HEAD and OPTIONS as the real parser does' do
    %w[POST PUT DELETE HEAD OPTIONS].each do |method|
      action = dynamic_action.merge(method:)
      result = python_request(action, dynamic_sample[:request])
      supported = %w[POST PUT DELETE].include?(method)
      if supported
        expect(result.fetch('body').fetch('widget')).to eq(JSON.parse(JSON.generate(dynamic_sample[:request])))
      else
        expect(result).to include('error' => 'ProtocolError', 'message' => "unsupported action method: #{method}")
      end
      renderers.each do |renderer|
        example = renderer.render(:example, context: dynamic_context(action:))
        expect(example[:status]).to eq(supported ? :code : :limitation)
      end
    end
  end

  it 'cross-checks missing global and per-object metadata against the real Python builder' do
    %i[global object].each do |scope|
      %i[hash hash_list].each do |layout|
        [true, false].each do |required|
          action = dynamic_action.merge(input: { layout:, namespace: :widget, parameters: {} }, meta: {
            scope => { input: { layout: :hash, namespace: false, parameters: { confirm: { type: 'Boolean', required: } } } }
          })
          params = layout == :hash ? {} : [{}]
          native = python_request(action, params)
          if required
            expect(native).to include('error' => 'ValidationError', 'message' => 'input parameters are not valid')
          else
            expect(native).not_to have_key('error')
          end
          [true, false].each do |status|
            renderers.each do |renderer|
              result = renderer.render(:example, context: dynamic_context(action:, sample: dynamic_sample.merge(request: params, status:)))
              expect(result[:status]).to eq(required ? :limitation : :code), result.inspect
            end
          end
        end
      end
    end
  end
end
