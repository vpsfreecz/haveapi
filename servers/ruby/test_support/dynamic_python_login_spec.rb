require 'spec_helper'
require 'open3'
require 'rack/mock'
require_relative 'dynamic_documentation_api'
require_relative '../spec/client_examples/dynamic_fixture'

RSpec.describe HaveAPI::ClientExamples::PythonClient do
  include DynamicExampleFixture

  [described_class, HaveAPI::ClientExamples::PythonAsyncClient].each do |renderer|
    it "preserves actual required token input in the rendered #{renderer.id} mapping and native builder" do
      request = Rack::MockRequest.new(DynamicDocumentationAPI.build.app)
      response = request.options('http://example.test/mount/v2/')
      expect(response.status).to eq(200), response.body
      envelope = JSON.parse(response.body)
      expect(envelope.fetch('status')).to be(true), envelope.inspect
      description = envelope.fetch('response')
      context = dynamic_context(description:)
      rendered = renderer.render(:auth, context:, auth_method: :token, auth_description: description.fetch('authentication').fetch('token'))
      expect(rendered[:status]).to eq(:code), rendered.inspect
      script = <<~PY
        import ast
        import json
        import sys
        from haveapi_client._protocol import CallContext, build_request, parse_description, parse_resources
        from haveapi_client.exceptions import ValidationError

        fixture = json.load(sys.stdin)
        tree = ast.parse(fixture["source"])
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Attribute) and node.func.attr == "begin_token_login"]
        assert len(calls) == 1
        params = ast.literal_eval(calls[0].args[0])
        description = parse_description(fixture["envelope"])
        action = parse_resources(description.authentication["token"]["resources"])["token"].actions["request"]
        assert action.input.parameters["lifetime"].required
        assert "fixed" in action.input.parameters["lifetime"].raw["validators"]["include"]["values"]
        assert not action.input.parameters["interval"].required
        context = CallContext(action, (), {}, 1)
        built = build_request(description, context, base_url=fixture["base_url"], params=params)
        body = json.loads(built.content)
        missing = dict(params)
        del missing["lifetime"]
        try:
            build_request(description, context, base_url=fixture["base_url"], params=missing)
        except ValidationError as error:
            errors = {key: list(value) for key, value in error.errors.items()}
        else:
            raise AssertionError("Missing required lifetime was accepted")
        print(json.dumps({"params": params, "body": body, "url": built.url, "missing_errors": errors}))
      PY
      root = File.expand_path('../../..', __dir__)
      output, status = Open3.capture2e(
        { 'PYTHONPATH' => File.join(root, 'clients/python/src'), 'PYTHONDONTWRITEBYTECODE' => '1' },
        File.join(root, 'clients/python/.venv/bin/python'), '-c', script,
        stdin_data: JSON.generate({ envelope:, source: rendered.fetch(:code), base_url: context.base_url })
      )
      expect(status).to be_success, output
      actual = JSON.parse(output)
      expected = { 'user' => 'user', 'password' => 'secret', 'scope' => 'scope', 'lifetime' => 'fixed' }
      expect(actual.fetch('params')).to eq(expected)
      expect(actual.fetch('body')).to eq('token' => expected)
      expect(actual.fetch('url')).to eq('https://api.example.test/mount/_auth/token/tokens')
      expect(actual.fetch('missing_errors')).to eq('lifetime' => ['required parameter is missing'])
    end
  end
end
