const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

function harness(fail = {}) {
  const requests = [];
  class XHR {
    constructor() { this.headers = {}; requests.push(this); }
    open(...args) { this.openArgs = args; this.url = args[1]; if (fail.open) throw new Error('open failed'); }
    setRequestHeader(name, value) { this.headers[name] = value; }
    send(body) { this.body = body; if (fail.send) throw new Error('send failed'); }
    respond(body, status = 200) {
      this.readyState = 4; this.status = status;
      this.responseText = typeof body === 'string' ? body : JSON.stringify(body);
      if (this.onreadystatechange) this.onreadystatechange();
    }
    abort() { this.aborted = true; if (this.onabort) this.onabort(); }
  }
  const context = {module: {exports: {}}, exports: {}, URL, Promise, AbortController,
    setTimeout, clearTimeout, console: {log() {}}, require: () => ({XMLHttpRequest: XHR})};
  vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../../dist/haveapi-client.js'), 'utf8'), context);
  return {HaveAPI: context.module.exports, requests};
}
const tick = () => new Promise(resolve => setImmediate(resolve));
const parameter = type => ({type});
function action(path, input = null, output = 'hash', namespace = 'widget', method = 'GET') {
  return {path, method, blocking: false, aliases: [], input: input && {layout: 'hash', namespace, parameters: input},
    output: output && {layout: output, namespace, parameters: {id: parameter('Integer'), name: parameter('String')}}};
}
function description() {
  const state = {show: action('/v1/states/{id}', null, 'hash', 'action_state'),
    poll: action('/v1/states/{id}/poll', {timeout: parameter('Float'), update_in: parameter('Float'),
      current: parameter('Integer'), total: parameter('Integer'), status: parameter('Boolean')}, 'hash', 'action_state')};
  const token = name => action('/v1/token/' + name, {user: parameter('String'), password: parameter('String'),
    lifetime: parameter('String'), token: parameter('String'), code: parameter('String')}, 'hash', 'token', 'POST');
  return {meta: {namespace: '_meta'}, authentication: {basic: {}, oauth2: {http_header: 'X-OAuth'},
    token: {http_header: 'X-Token', resources: {token: {resources: {}, actions: {request: token('request'), challenge: token('challenge')}}}}},
    resources: {widgets: {resources: {}, actions: {show: action('/v1/widgets/{id}'),
      run: {...action('/v1/widgets/{id}/run', null, 'hash', 'widget', 'POST'), blocking: true}}},
      action_state: {resources: {}, actions: state}}};
}
const described = data => ({status: true, version: '2.0', response: data});
const reply = (data, namespace = 'widget', meta = {}) => ({status: true, response: {[namespace]: data, _meta: meta}});

test('setup-free requests share query/body rules and snapshot namespaces/headers', async () => {
  const {HaveAPI, requests} = harness();
  const api = new HaveAPI.AsyncClient('https://api.example/api', {language: 'cs'});
  const spec = {method: 'GET', path: '/v1/widgets?existing=1', inputNamespace: 'widget', outputNamespace: 'widget',
    params: {name: 'a&b', cleared: null}, meta: {count: true}, headers: {'accept-language': 'en'}};
  const pending = api.request(spec);
  spec.outputNamespace = 'changed';
  const url = new URL(requests[0].url);
  assert.equal(url.pathname, '/api/v1/widgets');
  assert.equal(url.searchParams.get('widget[name]'), 'a&b');
  assert.equal(url.searchParams.get('widget[cleared]'), '');
  assert.equal(url.searchParams.get('_meta[count]'), 'true');
  assert.equal(Object.keys(requests[0].headers).filter(key => key.toLowerCase() === 'accept-language').length, 1);
  assert.equal(requests[0].headers['accept-language'], 'en');
  requests[0].respond(reply({id: 1}, 'widget', {total_count: 7}));
  const result = await pending;
  assert.equal(result.data.id, 1); assert.equal(result.meta.total_count, 7); assert.equal(result.httpStatus, 200);
  assert.deepEqual(Object.keys(result).sort(), ['data', 'envelope', 'httpStatus', 'meta']);
  const posted = api.request({method: 'POST', path: '/v1/widgets', inputNamespace: 'widget', outputNamespace: 'widget', params: {name: 'new'}, meta: {includes: 'owner'}});
  assert.deepEqual(JSON.parse(requests[1].body), {widget: {name: 'new'}, _meta: {includes: 'owner'}});
  requests[1].respond(reply(null), 201); assert.equal((await posted).data, null);
});

test('API, malformed envelopes/JSON, namespace and origin failures reject with structured detail', async () => {
  const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
  const failed = api.request({method: 'GET', path: '/bad'});
  const checked = assert.rejects(failed, error => error instanceof HaveAPI.AsyncError && error.kind === 'api' &&
    error.httpStatus === 403 && error.envelope.message === 'denied' && error.errors.name[0] === 'bad');
  requests[0].respond({status: false, message: 'denied', errors: {name: ['bad']}}, 403); await checked;
  for (const body of ['not json', {status: 'true', response: {}}, {status: true}, {status: true, response: {_meta: []}}]) {
    const pending = api.request({method: 'GET', path: '/bad'});
    const check = assert.rejects(pending, error => error.kind === 'protocol' && error.httpStatus === 200);
    requests[requests.length - 1].respond(body); await check;
  }
  const namespace = api.request({method: 'GET', path: '/bad', outputNamespace: 'missing'});
  const missing = assert.rejects(namespace, error => error.kind === 'protocol');
  requests[requests.length - 1].respond(reply({})); await missing;
  const count = requests.length;
  await assert.rejects(api.request({method: 'GET', path: '//evil.example/path'}), error => error.kind === 'protocol');
  await assert.rejects(api.request({method: 'GET', path: '/safe', headers: {'X-Test': 'a\nb'}}), error => error.kind === 'validation');
  assert.equal(requests.length, count);
});

for (const status of [200, 422]) {
  test(`nested application errors retain their rejection receipt at HTTP ${status}`, async () => {
    const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
    const body = {status: false, message: 'Validation failed', response: null,
      errors: {vps: {memory: ['too large'], limits: {disk: ['too small']}}, name: ['required']}};
    const pending = api.request({method: 'POST', path: '/vpses/123/start'});
    const checked = assert.rejects(pending, error => {
      assert.ok(error instanceof HaveAPI.AsyncError);
      assert.equal(error.kind, 'api');
      assert.equal(error.httpStatus, status);
      assert.equal(JSON.stringify(error.envelope), JSON.stringify(body));
      assert.equal(error.errors, error.envelope.errors);
      assert.equal(error.response.envelope, error.envelope);
      assert.equal(error.response.httpStatus, status);
      assert.equal(error.response.data, null);
      assert.equal(Object.keys(error.response.meta).length, 0);
      return true;
    });
    requests[0].respond(body, status); await checked;
    assert.equal(requests.length, 1);
  });
}

test('malformed nested error leaves and metadata remain protocol failures', async () => {
  const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
  for (const status of [200, 422]) {
    for (const errors of [{vps: {memory: 'too large'}}, {vps: {memory: [1]}}, {vps: null}, {vps: [{memory: ['bad']}]}]) {
      const pending = api.request({method: 'POST', path: '/vpses/123/start'});
      const checked = assert.rejects(pending, error => error.kind === 'protocol' &&
        error.httpStatus === status && error.envelope === undefined && error.response === undefined);
      requests[requests.length - 1].respond({status: false, response: null, errors}, status); await checked;
    }
    const pending = api.request({method: 'POST', path: '/vpses/123/start'});
    const checked = assert.rejects(pending, error => error.kind === 'protocol' &&
      error.httpStatus === status && error.message === 'Invalid response metadata');
    requests[requests.length - 1].respond({status: false, errors: {vps: {memory: ['bad']}}, response: {_meta: []}}, status);
    await checked;
  }
});

test('transport errors, pre/inflight abort and timeout settle once and release listeners', async () => {
  for (const fail of [{open: true}, {send: true}]) {
    const {HaveAPI} = harness(fail);
    await assert.rejects(new HaveAPI.AsyncClient('https://api.example').request({method: 'GET', path: '/x'}), error => error.kind === 'transport');
  }
  const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
  const before = new AbortController(); before.abort();
  await assert.rejects(api.request({method: 'GET', path: '/x', signal: before.signal}), error => error.kind === 'aborted' && error.name === 'AbortError');
  assert.equal(requests.length, 0);
  const controller = new AbortController();
  const pending = api.request({method: 'GET', path: '/x', signal: controller.signal});
  const checked = assert.rejects(pending, error => error.kind === 'aborted');
  controller.abort(); await checked;
  assert.equal(requests[0].aborted, true); assert.equal(requests[0].onreadystatechange, null); assert.equal(requests[0].onerror, null);
  const timed = api.request({method: 'GET', path: '/x', timeoutMs: 10});
  await assert.rejects(timed, error => error.kind === 'timeout'); assert.equal(requests[1].aborted, true);
  const network = api.request({method: 'GET', path: '/x'});
  const errored = assert.rejects(network, error => error.kind === 'transport'); requests[2].onerror(); await errored;
});

test('token MFA and authorized description publish independently and atomically', async () => {
  const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
  const auth = api.authenticate('token', {user: 'u', password: 'p', onChallenge: async name => {
    assert.equal(name, 'challenge'); return {code: '123'};
  }});
  await tick(); requests[0].respond(described(description())); await tick();
  requests[1].respond(reply({complete: false, token: 'temporary', next_action: 'challenge'}, 'token')); await tick();
  assert.equal(JSON.parse(requests[2].body).token.token, 'temporary');
  requests[2].respond(reply({complete: true, token: 'final'}, 'token')); await tick();
  assert.equal(requests[3].headers['X-Token'], 'final'); requests[3].respond(described(description())); await auth;
  const refresh = api.authenticate('token', {token: 'replacement'}); await tick();
  const failed = assert.rejects(refresh, error => error.httpStatus === 401);
  requests[4].respond({status: false, message: 'rejected'}, 401); await failed;
  const lowlevel = api.request({method: 'GET', path: '/ready'});
  assert.equal(requests[5].headers['X-Token'], 'final'); requests[5].respond(reply({})); await lowlevel;
});

test('queued lifecycle updates, stale publication and callback-form rejection', async () => {
  const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
  const setup = api.setup(); const auth = api.authenticate('basic', {user: 'u', password: 'p'});
  await tick(); assert.equal(requests.length, 1); requests[0].respond(described(description())); await setup; await tick();
  assert.equal(requests.length, 2); assert.equal(requests[1].openArgs[3], 'u'); requests[1].respond(described(description())); await auth;
  const older = api.setup(); await tick(); api.useDescription({...description(), resources: {}});
  const stale = assert.rejects(older, error => error.reason === 'stale-binding'); requests[2].respond(described(description())); await stale;
  assert.equal(api.resources.length, 0);
  await assert.rejects(api.setup(() => {}), error => error.kind === 'validation');
  await assert.rejects(api.authenticate('token', {token: 'x'}, () => {}), error => error.kind === 'validation');
});

test('setup/auth failure paths retain rejection channels and recover the lifecycle queue', async () => {
  const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
  const setup = api.setup(); await tick(); const failed = assert.rejects(setup, error => error.kind === 'protocol');
  requests[0].respond({status: true, version: '9.0', response: description()}); await failed;
  api.useDescription(description());
  await assert.rejects(api.authenticate('unsupported', {}), error => error.kind === 'authentication');
  await assert.rejects(api.authenticate('oauth2', {}), error => error.kind === 'authentication');
  const auth = api.authenticate('token', {user: 'u', password: 'p'}); await tick();
  const challenge = assert.rejects(auth, error => error.kind === 'authentication');
  requests[1].respond(reply({complete: false, token: 'temporary', next_action: 'challenge'}, 'token')); await challenge;
  const oauth = api.authenticate('oauth2', {access_token: {access_token: 'oauth'}}); await tick();
  assert.equal(requests[2].headers['X-OAuth'], 'oauth'); requests[2].respond(described(description())); await oauth;
});

async function started(h) {
  const api = new h.HaveAPI.AsyncClient('https://api.example'); api.useDescription(description());
  const running = api.resource('widgets').action('run').invoke(7); h.requests[0].respond(reply({}, 'widget', {action_state_id: 9}));
  return {api, result: await running};
}
const state = (finished, status = true) => reply({id: 9, finished, status, current: finished ? 2 : 0, total: 2, can_cancel: true}, 'action_state');

test('server completion is explicit, reports progress and rejects failed terminal execution', async () => {
  const h = harness(); const {api, result} = await started(h); assert.equal(h.requests.length, 1);
  const progress = [];
  const waiting = api.waitForCompletion(result, {timeoutMs: 1000, onStateChange: s => progress.push(s.progress.current)});
  h.requests[1].respond(state(false)); await tick();
  const failed = assert.rejects(waiting, error => error.kind === 'action-failed' && error.response === result.response && error.state.status === false);
  h.requests[2].respond(state(true, false)); await failed; assert.deepEqual(progress, [0, 2]);
  const h2 = harness(); const ready = await started(h2);
  const done = ready.api.waitForCompletion(ready.result, {timeoutMs: 1000}); h2.requests[1].respond(state(true));
  assert.equal((await done).state.finished, true);
});

test('completion poll errors, abort and overall timeout settle with original receipt', async () => {
  const h = harness(); const {api, result} = await started(h);
  const waiting = api.waitForCompletion(result, {timeoutMs: 1000});
  const failed = assert.rejects(waiting, error => error.kind === 'api' && error.httpStatus === 404 && error.response === result.response && error.envelope.message === 'missing');
  h.requests[1].respond({status: false, message: 'missing'}, 404); await failed;
  const controller = new AbortController(); controller.abort();
  await assert.rejects(api.waitForCompletion(result, {timeoutMs: 1000, signal: controller.signal}), error => error.kind === 'aborted');
  assert.equal(h.requests.length, 2);
  const timeout = api.waitForCompletion(result, {timeoutMs: 10});
  await assert.rejects(timeout, error => error.kind === 'timeout' && error.response === result.response);
  assert.equal(h.requests[2].aborted, true);
});

test('OPTIONS version documents unwrap response root without an action namespace', async () => {
  const {HaveAPI, requests} = harness();
  const api = new HaveAPI.AsyncClient('https://api.example', {version: 2});
  const versions = api.availableVersions();
  assert.equal(requests[0].url, 'https://api.example/?describe=versions');
  requests[0].respond({version: '2.0', status: true, response: {versions: [1, 2], default: 2}, message: null, errors: null});
  assert.deepEqual(JSON.parse(JSON.stringify(await versions)), {versions: [1, 2], default: 2});
  const setup = api.setup(); await tick();
  assert.equal(requests[1].url, 'https://api.example/v2/');
  requests[1].respond({version: '2.0', status: true, response: description(), message: null, errors: null});
  await setup;
  const invalid = api.availableVersions(); const rejected = assert.rejects(invalid, error => error.kind === 'protocol');
  requests[2].respond(described({wrong_namespace: {versions: [1], default: 1}})); await rejected;
});

test('shared validation accepts null-prototype inputs and own method/prototype names', async () => {
  const {HaveAPI, requests} = harness(); const api = new HaveAPI.AsyncClient('https://api.example');
  const doc = description(); const parameters = Object.create(null);
  parameters.hasOwnProperty = parameter('String'); parameters.__proto__ = parameter('Integer');
  doc.resources.widgets.actions.validate = action('/v1/validate', parameters, 'hash', 'widget', 'POST');
  api.useDescription(doc);
  const params = Object.create(null); params.hasOwnProperty = 'local'; params.__proto__ = '42';
  const pending = api.resource('widgets').action('validate').invoke({params});
  assert.deepEqual(JSON.parse(requests[0].body).widget, JSON.parse('{"hasOwnProperty":"local","__proto__":42}'));
  requests[0].respond(reply({})); await pending;
  params.__proto__ = 'not an integer';
  await assert.rejects(api.resource('widgets').action('validate').invoke({params}), error =>
    error.kind === 'validation' && Array.isArray(error.errors.__proto__));
  assert.equal(requests.length, 1);
});
