require 'spec_helper'
require 'open3'
require 'rack/mock'
require_relative '../../test_support/dynamic_documentation_api'

RSpec.describe DynamicDocumentationAPI do
  it 'uses real mounted descriptor routes for callback and async token challenges and nested actions' do
    request = Rack::MockRequest.new(described_class.build.app)
    headers = { 'HTTP_AUTHORIZATION' => "Basic #{['fixture-user:fixture-password'].pack('m0')}" }
    envelope = JSON.parse(request.options('http://example.test/mount/v2/', headers).body)
    model = envelope.fetch('response')
    token = model.fetch('authentication').fetch('token').fetch('resources').fetch('token').fetch('actions')
    action = model.fetch('resources').fetch('constructor').fetch('resources').fetch('resources').fetch('actions').fetch('new')
    expect(token.fetch('request').fetch('path')).to eq('/mount/_auth/token/tokens')
    expect(action.fetch('path')).to eq('/mount/v2/parents/{parent_id}/children/{widget_id}')
    params = action.fetch('examples').first.fetch('request')
    post = lambda do |path, body, extra = {}|
      response = request.post("http://example.test#{path}", extra.merge('CONTENT_TYPE' => 'application/json', input: JSON.generate(body)))
      expect(response.status).to eq(200), response.body
      JSON.parse(response.body)
    end
    challenge = post.call(token.fetch('request').fetch('path'), { token: {
      user: 'fixture-user', password: 'fixture-password', scope: 'all', lifetime: 'renewable_auto'
    } })
    completed = post.call(token.fetch('verify').fetch('path'), { token: { token: 'fixture-challenge', code: '123456' } })
    action_path = action.fetch('path').sub('{parent_id}', '7').sub('{widget_id}', 'name%20with%20space')
    result = post.call(action_path, { widget: params }, { 'HTTP_X_HAVEAPI_AUTH_TOKEN' => 'fixture-token' })
    data = { envelope:, challenge:, completed:, result:, params:, action_path: }
    script = <<~JS
      const assert = require('node:assert/strict');
      const {harness, tick} = require(process.argv[1]);
      const {HaveAPI, requests} = harness();
      const data = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
      const model = data.envelope.response;
      const auth = model.authentication.token.resources.token.actions;
      async function check() {
        const callback = new HaveAPI.CallbackClient('http://example.test/mount/', {version:'2'});
        let ready = false;
        callback.authenticate('token', {user:'fixture-user', password:'fixture-password', scope:'all', callback: () => ({code:'123456'})},
          (_, ok) => { ready = ok; });
        // Parse actual discovery JSON inside the bundle's VM, matching the real XHR boundary.
        assert.equal(requests[0].url, 'http://example.test/mount/v2/'); requests[0].respond(data.envelope);
        assert.equal(requests[1].url, 'http://example.test' + auth.request.path); requests[1].respond(data.challenge);
        assert.equal(requests[2].url, 'http://example.test' + auth.verify.path); requests[2].respond(data.completed);
        assert.equal(requests[3].url, 'http://example.test/mount/v2/'); requests[3].respond(data.envelope); assert.equal(ready, true);
        const resource = HaveAPI.CallbackClient.findResource(callback, ['constructor','resources']);
        HaveAPI.CallbackClient.findAction(resource, 'new').directInvoke(7, 'name with space', {params:data.params});
        assert.equal(requests[4].url, 'http://example.test' + data.action_path); requests[4].respond(data.result);
        const api = new HaveAPI.AsyncClient('http://example.test/mount/', {version:'2'}); api.useDescription(model);
        const authenticating = api.authenticate('token', {user:'fixture-user', password:'fixture-password', scope:'all', onChallenge: () => ({code:'123456'})});
        await tick(); assert.equal(requests[5].url, 'http://example.test' + auth.request.path); requests[5].respond(data.challenge);
        await tick(); assert.equal(requests[6].url, 'http://example.test' + auth.verify.path); requests[6].respond(data.completed);
        await tick(); assert.equal(requests[7].url, 'http://example.test/mount/v2/'); requests[7].respond(data.envelope); await authenticating;
        const invoked = api.resource('constructor').resource('resources').action('new')(7, 'name with space', {params:data.params});
        assert.equal(requests[8].url, 'http://example.test' + data.action_path); requests[8].respond(data.result);
        assert.equal((await invoked).value.marker, 'DOC_SUCCESS');
        assert.equal(requests.length, 9);
      }
      check().catch(error => {console.error(error); process.exitCode = 1;});
    JS
    helper = File.expand_path('../../../../clients/js/test/helpers/async_bundle.cjs', __dir__)
    output, status = Open3.capture2e('node', '-e', script, helper, stdin_data: JSON.generate(data))
    expect(status).to be_success, output
  end
end
