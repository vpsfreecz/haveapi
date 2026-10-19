const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const bundlePath = path.resolve(__dirname, '../../dist/haveapi-client.js');
const bundle = fs.readFileSync(bundlePath, 'utf8');

// Exercise the distributed artifact without loading a server or npm dependencies.
// Promise and AbortController are deliberately absent: callback consumers must
// retain their existing runtime requirements when AsyncClient is added.
function loadBundle(mode = 'commonjs') {
  const requests = [];
  const imports = [];
  class FakeXHR {
    constructor() {
      this.headers = {};
      requests.push(this);
    }
    open(...args) { this.openArgs = args; }
    setRequestHeader(name, value) { this.headers[name] = value; }
    send(body) { this.body = body; }
    respond(status, value) {
      this.status = status;
      this.responseText = JSON.stringify(value);
      this.readyState = 4;
      this.onreadystatechange();
    }
  }
  const context = {
    console: { log() {}, warn() {}, error() {} }, URL,
    setTimeout, clearTimeout, Promise: undefined, AbortController: undefined,
  };
  let amd;
  if (mode === 'commonjs') {
    context.module = { exports: {} };
    context.exports = context.module.exports;
    context.require = (name) => {
      imports.push(name);
      assert.equal(name, 'xmlhttprequest');
      return { XMLHttpRequest: FakeXHR };
    };
  } else {
    context.window = { XMLHttpRequest: FakeXHR };
    if (mode === 'amd') {
      context.define = (dependencies, factory) => {
        assert.equal(dependencies.length, 0);
        amd = factory();
      };
      context.define.amd = {};
    }
  }
  vm.runInNewContext(bundle, context, { filename: bundlePath });
  const HaveAPI = mode === 'commonjs' ? context.module.exports : mode === 'amd' ? amd : context.HaveAPI;
  return { HaveAPI, requests, imports, context };
}

function action(pathname, overrides = {}) {
  return {
    aliases: [], blocking: false, method: 'GET', path: pathname,
    input: { layout: 'hash', namespace: 'widget', parameters: {} },
    output: { layout: 'hash', namespace: 'widget', parameters: {} },
    ...overrides,
  };
}

function description() {
  return {
    authentication: { basic: {} }, meta: { namespace: '_meta' },
    resources: {
      widgets: {
        actions: {
          show: action('/v1/widgets/{widget_id}', { aliases: ['get'] }),
          list: action('/v1/widgets'),
          update: action('/v1/widgets/{widget_id}', {
            method: 'PUT',
            input: { layout: 'hash', namespace: 'widget', parameters: { count: { type: 'Integer' } } },
          }),
        },
        resources: {
          children: {
            actions: { destroy: action('/v1/widgets/{widget_id}/children/{child_id}', { method: 'DELETE', input: null, output: null }) },
            resources: {},
          },
        },
      },
    },
  };
}

function prepared(mode) {
  const loaded = loadBundle(mode);
  const client = new loaded.HaveAPI.Client('https://api.example', {});
  client.useDescription(description());
  return { ...loaded, client };
}

function reply(data = {}, meta = {}) {
  return { status: true, message: null, errors: null, response: { widget: data, _meta: meta } };
}

for (const mode of ['commonjs', 'browser', 'amd']) {
  test(`${mode} retains Client/CallbackClient identity and callbacks without async runtime globals`, () => {
    const { HaveAPI, imports, requests, context } = loadBundle(mode);
    assert.equal(typeof HaveAPI.Client, 'function');
    assert.equal(HaveAPI.CallbackClient, HaveAPI.Client);
    assert.equal(HaveAPI.CallbackClient.name, 'Client');
    assert.equal(HaveAPI.CallbackClient.prototype, HaveAPI.Client.prototype);
    assert.equal(HaveAPI.default, undefined);
    for (const name of ['Action', 'ActionState', 'BaseResource', 'Hooks', 'Http', 'Resource', 'ResourceInstance', 'ResourceInstanceList', 'Response', 'LocalResponse']) {
      assert.equal(typeof HaveAPI.Client[name], 'function', name);
      assert.equal(HaveAPI.CallbackClient[name], HaveAPI.Client[name], name);
    }
    assert.equal(typeof HaveAPI.Client.Authentication, 'object');
    assert.equal(HaveAPI.CallbackClient.Authentication, HaveAPI.Client.Authentication);
    assert.equal(typeof HaveAPI.Client.Exceptions.ProtocolError, 'function');
    assert.equal(HaveAPI.CallbackClient.Exceptions, HaveAPI.Client.Exceptions);
    assert.equal(typeof HaveAPI.Client.ActionState.Progress, 'function');
    assert.deepEqual(imports, mode === 'commonjs' ? ['xmlhttprequest'] : []);
    const callbackClient = new HaveAPI.CallbackClient('https://api.example', {});
    const legacyClient = new HaveAPI.Client('https://api.example', {});
    for (const instance of [callbackClient, legacyClient]) {
      assert.equal(instance instanceof HaveAPI.Client, true);
      assert.equal(instance instanceof HaveAPI.CallbackClient, true);
      assert.equal(instance.constructor, HaveAPI.Client);
      assert.equal(Object.getPrototypeOf(instance), HaveAPI.Client.prototype);
    }
    callbackClient.useDescription(description());
    let received;
    assert.equal(callbackClient.widgets.show(7, (owner, response) => {
      received = [owner, response];
    }), undefined);
    assert.equal(received, undefined);
    requests[0].respond(200, reply({ count: 2 }));
    assert.equal(received[0], callbackClient);
    assert.equal(received[1] instanceof HaveAPI.CallbackClient.Response, true);
    assert.equal(received[1].response().count, 2);
    assert.equal(context.Promise, undefined);
    assert.equal(context.AbortController, undefined);
    const { client } = prepared(mode);
    assert.equal(client.widgets.show(3), undefined);
  });
}

test('setup returns undefined before the deferred callback and preserves hook ordering/this', () => {
  const { HaveAPI, requests } = loadBundle();
  const client = new HaveAPI.Client('https://api.example');
  const events = [];
  const hooks = [];
  function hook() { hooks.push({ receiver: this, args: arguments.length }); events.push('hook'); }
  assert.equal(client.after('setup', hook), undefined);
  assert.equal(client.setup((receivedClient, status) => {
    assert.equal(receivedClient, client);
    assert.equal(status, true);
    events.push('callback');
  }), undefined);
  assert.deepEqual(events, []);
  requests[0].respond(200, { version: HaveAPI.Client.ProtocolVersion, response: description() });
  assert.deepEqual(events, ['callback', 'hook']);
  assert.equal(client.after('setup', hook), undefined);
  assert.deepEqual(events, ['callback', 'hook', 'hook']);
  // Legacy Hooks.apply supplies its saved arguments as this, not as arguments.
  for (const observed of hooks) {
    assert.equal(observed.args, 0);
    assert.equal(Array.isArray(observed.receiver), true);
  }
  assert.equal(hooks[0].receiver[0], client);
  assert.equal(hooks[0].receiver[1], true);
  // A hook queued before the event leaves the saved late-hook receiver empty.
  assert.equal(hooks[1].receiver.length, 0);
});

test('setup failure is a callback result, while unsupported authentication throws synchronously', () => {
  const { HaveAPI, requests } = loadBundle();
  const client = new HaveAPI.Client('https://api.example');
  let failed;
  assert.equal(client.setup((c, status) => { failed = [c, status]; }), undefined);
  requests[0].respond(200, {});
  assert.equal(failed[0], client);
  assert.equal(failed[1], false);
  client.useDescription(description());
  assert.throws(() => client.authenticate('missing', {}, () => {}), { name: 'TypeError' });
});

test('basic authentication and logout keep callback arguments and undefined returns', () => {
  const { client } = prepared();
  const events = [];
  client.after('authenticated', function() { events.push('hook'); });
  assert.equal(client.authenticate('basic', { user: 'alice', password: 'secret' }, (c, status) => {
    assert.equal(c, client);
    assert.equal(status, true);
    events.push('callback');
  }, false), undefined);
  assert.deepEqual(events, ['callback', 'hook']);
  assert.equal(client.authProvider.credentials().user, 'alice');
  assert.equal(client.logout((c, status) => {
    assert.equal(c, client);
    assert.equal(status, true);
    events.push('logout');
  }), undefined);
  assert.equal(client.resources.length, 0);
  assert.equal(client._private.description, null);
  assert.deepEqual(events, ['callback', 'hook', 'logout']);
});

test('callable actions/resources keep aliases, prototypes, descriptors and detached invocation', () => {
  const { HaveAPI, client, requests } = prepared();
  const resource = client.widgets;
  const show = resource.show;
  assert.equal(typeof resource, 'function');
  assert.equal(typeof show, 'function');
  assert.equal(resource instanceof HaveAPI.Client.Resource, true);
  assert.equal(resource instanceof HaveAPI.Client.BaseResource, true);
  assert.equal(show instanceof HaveAPI.Client.Action, true);
  assert.equal(resource.get, show);
  assert.equal(Object.getPrototypeOf(Object.getPrototypeOf(resource)), HaveAPI.Client.Resource.prototype);
  assert.equal(Object.getPrototypeOf(Object.getPrototypeOf(show)), HaveAPI.Client.Action.prototype);
  assert.equal(Object.hasOwn(resource, '_private'), false);
  assert.equal(Object.hasOwn(show, 'client'), false);
  assert.equal(Object.getOwnPropertyDescriptor(client, 'widgets').enumerable, true);
  assert.equal(Object.getOwnPropertyDescriptor(Object.getPrototypeOf(resource), 'show').writable, true);
  // These callable objects historically replace Function.prototype entirely.
  assert.equal(show.call, undefined);
  assert.equal(resource.bind, undefined);
  let received;
  assert.equal(show(7, (c, result) => { received = [c, result]; }), undefined);
  assert.equal(received, undefined);
  requests[0].respond(200, reply({ count: 2 }));
  assert.equal(received[0], client);
  assert.equal(received[1] instanceof HaveAPI.Client.Response, true);
  assert.equal(received[1].response().count, 2);
});

test('curried nested IDs and callback-free calls issue independent requests', () => {
  const { client, requests } = prepared();
  assert.equal(client.widgets(12).children(34).destroy(), undefined);
  assert.equal(client.widgets(56).children.destroy(78), undefined);
  assert.equal(requests[0].openArgs[1], 'https://api.example/v1/widgets/12/children/34');
  assert.equal(requests[1].openArgs[1], 'https://api.example/v1/widgets/56/children/78');
  requests[0].respond(200, { status: true, response: null });
  requests[1].respond(200, { status: true, response: null });
  assert.equal(client.widgets._private.args.length, 0);
});

test('local validation calls back synchronously without HTTP and preserves LocalResponse', () => {
  const { HaveAPI, client, requests } = prepared();
  const events = [];
  assert.equal(client.widgets.update(7, { count: 'bad' }, (c, result) => {
    assert.equal(c, client);
    assert.equal(result instanceof HaveAPI.Client.LocalResponse, true);
    assert.equal(result instanceof HaveAPI.Client.Response, true);
    assert.equal(result.isOk(), false);
    assert.match(result.envelope.errors.count[0], /valid integer/);
    events.push('reply');
  }), undefined);
  events.push('returned');
  assert.deepEqual(events, ['reply', 'returned']);
  assert.equal(requests.length, 0);
  assert.equal(client.widgets.update(7, { count: 'bad' }), undefined);
  assert.equal(requests.length, 0);
});

test('unresolved IDs, transport failures and callback exceptions remain synchronous throws', () => {
  const { client } = prepared();
  assert.throws(() => client.widgets.show(), (error) => error.name === 'UnresolvedArguments');
  client._private.http.request = () => { throw new Error('transport failed'); };
  const show = client.widgets.show;
  show.providePath('/v1/widgets/7');
  assert.throws(() => show.directInvoke(), /transport failed/);
  assert.equal(show.preparedPath, null);
  client._private.http.request = (options) => options.callback(200, reply());
  assert.throws(() => show(7, () => { throw new Error('callback failed'); }), /callback failed/);
});

test('raw and rich replies retain namespace/meta, list helpers and attribute descriptors', () => {
  const { HaveAPI, client } = prepared();
  const objectDescription = description().resources.widgets;
  objectDescription.actions.show.output = { layout: 'object', namespace: 'widget', parameters: { id: { type: 'Integer' }, label: { type: 'String' } } };
  objectDescription.actions.list.output = { layout: 'object_list', namespace: 'widget', parameters: { id: { type: 'Integer' }, label: { type: 'String' } } };
  client.useDescription({ ...description(), resources: { widgets: objectDescription } });
  client._private.http.request = (options) => {
    options.callback(200, reply([{ id: 7, label: 'first', _meta: { path_params: [7] } }], { total_count: 4 }));
  };
  let list;
  assert.equal(client.widgets.list((c, result) => { list = result; }), undefined);
  assert.equal(list instanceof HaveAPI.Client.ResourceInstanceList, true);
  assert.equal(list.length, 1);
  assert.equal(list.totalCount, 4);
  assert.equal(list.first(), list.last());
  assert.equal(list.itemAt(0), list.first());
  assert.equal(list.itemAt(9), undefined);
  assert.equal(list.apiResponse().meta().total_count, 4);
  assert.equal(list.isOk(), true);
  let iterated;
  assert.equal(list.each((item) => { iterated = item; }), undefined);
  const item = list.first();
  assert.equal(iterated, item);
  assert.equal(item instanceof HaveAPI.Client.ResourceInstance, true);
  const descriptor = Object.getOwnPropertyDescriptor(item, 'label');
  assert.equal(typeof descriptor.get, 'function');
  assert.equal(typeof descriptor.set, 'function');
  assert.equal(descriptor.enumerable, false);
  assert.equal(descriptor.configurable, false);
  item.label = 'changed';
  assert.equal(item.label, 'changed');
  assert.equal(item.show.providedIdArgs.length, 0);
  assert.equal(item.show.args[0], 7);
  let resolved;
  assert.equal(item.whenResolved((c, value) => { resolved = [c, value]; }), undefined);
  assert.equal(resolved[0], client);
  assert.equal(resolved[1], item);
  let raw;
  assert.equal(client.widgets.show.directInvoke(7, (c, result) => { raw = result; }), undefined);
  assert.equal(raw instanceof HaveAPI.Client.Response, true);
  assert.equal(raw.meta().total_count, 4);
});

test('ActionState stop/cancel and progress retain local callback-era behavior', () => {
  const { HaveAPI } = loadBundle();
  const state = new HaveAPI.Client.ActionState({ id: 7, current: 2, total: 4, unit: 'items', can_cancel: true });
  assert.equal(state.progress.toString(), '2/4 items');
  assert.equal(state.shouldStop(), false);
  assert.equal(state.shouldCancel(), false);
  assert.equal(state.stop(), undefined);
  const options = { onReply() {} };
  assert.equal(state.cancel(options), undefined);
  assert.equal(state.shouldStop(), true);
  assert.equal(state.shouldCancel(), true);
  assert.equal(state.cancelOpts, options);
});
