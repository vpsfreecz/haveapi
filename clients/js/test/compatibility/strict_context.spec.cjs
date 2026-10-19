const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const bundlePath = path.resolve(__dirname, '../../dist/haveapi-client.js');
const bundle = fs.readFileSync(bundlePath, 'utf8');

function loadBundle(host, strict) {
  const requests = [];
  const imports = [];
  class FakeXHR {
    constructor() { this.headers = {}; requests.push(this); }
    open(method, url) { this.method = method; this.url = url; }
    setRequestHeader(name, value) { this.headers[name] = value; }
    send(body) { this.body = body; }
    respond(response, status = 200) {
      this.status = status;
      this.responseText = JSON.stringify(response);
      this.readyState = 4;
      this.onreadystatechange();
    }
  }
  const context = vm.createContext({
    console: { log() {}, warn() {}, error() {} }, URL, setTimeout, clearTimeout,
    globalThis: undefined, Promise: undefined, AbortController: undefined,
    module: { exports: {} },
    require(name) {
      imports.push(name);
      assert.equal(name, 'xmlhttprequest');
      return { XMLHttpRequest: FakeXHR };
    }
  });
  context.exports = context.module.exports;
  // Expose each host independently. Worker-like transport uses the existing
  // CommonJS fake XHR; only the global-object fallback is under test here.
  const globalObject = vm.runInContext('this', context);
  context[{ browser: 'window', worker: 'self', node: 'global' }[host]] = globalObject;
  if (host === 'browser') context.XMLHttpRequest = FakeXHR;
  const source = strict
    ? '(function(module, exports) { "use strict";\n' + bundle + '\n})(module, exports);'
    : bundle;
  vm.runInContext(source, context, { filename: bundlePath });
  return { context, requests, imports, HaveAPI: context.module.exports };
}

function description() {
  const parameters = { id: { type: 'Integer' }, count: { type: 'Integer' } };
  const action = (method, input) => ({
    method, path: '/v1/widgets/{widget_id}', aliases: [], blocking: false,
    input, output: { layout: 'object', namespace: 'widget', parameters }
  });
  return {
    authentication: {}, meta: { namespace: '_meta' },
    resources: { widgets: { resources: {}, actions: {
      show: action('GET', null),
      update: action('PUT', { layout: 'hash', namespace: 'widget', parameters: { count: parameters.count } })
    } } }
  };
}

function exerciseCallbacks(loaded) {
  const { HaveAPI, context, requests } = loaded;
  assert.equal(typeof HaveAPI.Client, 'function');
  assert.equal(HaveAPI.Client.name, 'Client');
  assert.equal(HaveAPI.default, undefined);
  for (const name of ['Action', 'Resource', 'ResourceInstance', 'Response', 'Hooks']) {
    assert.equal(typeof HaveAPI.Client[name], 'function', name);
  }
  assert.equal(context.Authentication, HaveAPI.Client.Authentication);
  const client = new HaveAPI.Client('https://api.example', { version: 1 });
  let setup;
  assert.equal(client.setup((owner, status) => { setup = [owner, status]; }), undefined);
  assert.equal(setup, undefined);
  assert.equal(requests[0].method, 'OPTIONS');
  assert.equal(requests[0].url, 'https://api.example/v1/');
  // A compatible minor mismatch exercises both legacy version globals.
  requests[0].respond({ version: '2.1', status: true, response: description() });
  assert.equal(setup[0], client);
  assert.equal(setup[1], true);
  assert.deepEqual(Array.from(context.v1), ['2', '1']);
  assert.deepEqual(Array.from(context.v2), ['2', '0']);
  assert.equal(typeof client.widgets, 'function');
  assert.equal(typeof client.widgets.show, 'function');
  assert.equal(client.widgets instanceof HaveAPI.Client.Resource, true);
  assert.equal(client.widgets.show instanceof HaveAPI.Client.Action, true);
  let instance;
  assert.equal(client.widgets.show(7, (owner, value) => {
    assert.equal(owner, client);
    instance = value;
  }), undefined);
  assert.equal(instance, undefined);
  assert.equal(requests[1].method, 'GET');
  assert.equal(requests[1].url, 'https://api.example/v1/widgets/7');
  requests[1].respond({ status: true, response: { widget: { id: 7, count: 4 }, _meta: { path_params: [7] } } });
  assert.equal(instance instanceof HaveAPI.Client.ResourceInstance, true);
  assert.equal(instance.count, 4);
  assert.equal(instance.apiResponse().isOk(), true);
  context.ret = { previous: true };
  const params = instance.defaultParams(client.widgets.update);
  assert.equal(params, context.ret);
  assert.deepEqual(Object.keys(params), ['count']);
  assert.equal(params.count, 4);
  assert.equal(params.previous, undefined);
  assert.equal(context.globalThis, undefined);
  assert.equal(context.Promise, undefined);
  assert.equal(context.AbortController, undefined);
  return { client, instance };
}

for (const host of ['browser', 'worker', 'node']) {
  for (const strict of [false, true]) {
    test(`${host} ${strict ? 'strict wrapper' : 'raw bundle'} retains callback/global parity without globalThis or async primitives`, () => {
      const loaded = loadBundle(host, strict);
      exerciseCallbacks(loaded);
      assert.deepEqual(loaded.imports, host === 'browser' ? [] : ['xmlhttprequest']);
    });
  }
}

for (const strict of [false, true]) {
  test(`${strict ? 'strict wrapper' : 'raw bundle'} keeps live Authentication and defaultParams global reads`, () => {
    const loaded = loadBundle('node', strict);
    const { context, HaveAPI } = loaded;
    const { client, instance } = exerciseCallbacks(loaded);
    const original = context.Authentication;
    const replacement = { providers: {} };
    context.Authentication = replacement;
    let providerArgs;
    function CustomProvider(owner, options, providerDescription) {
      providerArgs = [owner, options, providerDescription];
      this.setup = callback => callback(owner, true);
    }
    assert.equal(original.registerProvider('custom', CustomProvider), undefined);
    assert.equal(replacement.providers.custom, CustomProvider);
    assert.equal(original.providers.custom, undefined);
    assert.equal(HaveAPI.Client.Authentication, original);
    const options = { marker: 'live registry' };
    let authenticated;
    assert.equal(client.authenticate('custom', options, (owner, status) => {
      authenticated = [owner, status];
    }, false), undefined);
    assert.deepEqual(providerArgs, [client, options, undefined]);
    assert.deepEqual(authenticated, [client, true]);

    const replacedParams = { replaced: true };
    Object.defineProperty(instance._private.attributes, 'count', {
      configurable: true, enumerable: true,
      get() { context.ret = replacedParams; return 9; }
    });
    // The getter changes the global during the assignment. Returning a cached
    // local instead of the live global would change this callback-era result.
    assert.equal(instance.defaultParams(client.widgets.update), replacedParams);
    assert.deepEqual(replacedParams, { replaced: true });
  });
}
