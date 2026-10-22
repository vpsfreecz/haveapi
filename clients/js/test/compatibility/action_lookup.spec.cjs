const assert = require('node:assert/strict');
const { test } = require('node:test');
const { CallbackClient, Client } = require('../../dist/haveapi-client.js');

function action(aliases = []) {
  return {
    aliases, method: 'POST', path: '/mount/v2/widgets/{id}', blocking: false,
    input: {layout: 'hash', namespace: 'widget', parameters: {count: {type: 'Integer'}}},
    output: {layout: 'hash', namespace: 'widget', parameters: {}},
  };
}

function fixture(actions) {
  const client = new CallbackClient('https://example.test/mount/', {version: 2});
  client.useDescription({authentication: {}, meta: {namespace: '_meta'}, resources: {
    setup: {actions, resources: {}},
  }});
  return {client, resource: CallbackClient.findResource(client, ['setup'])};
}

test('typed action lookup retains helper/unsafe canonical names without clobbering properties', () => {
  const actions = Object.create(null);
  for (const name of ['show', 'actions', 'resources', 'new', '__proto__', 'constructor', 'length'])
    actions[name] = action();
  const {client, resource} = fixture(actions);
  assert.equal(CallbackClient, Client);
  assert.equal(typeof client.setup, 'function');
  assert.deepEqual(resource.actions, Object.keys(actions));
  assert.ok(Array.isArray(resource.resources));
  assert.equal(typeof resource.new, 'function');
  for (const name of Object.keys(actions))
    assert.equal(CallbackClient.findAction(resource, name).description, actions[name]);
  assert.equal(resource.show, CallbackClient.findAction(resource, 'show'));
});

test('canonical action wins alias collisions, unique aliases resolve, ambiguous aliases fail', () => {
  const {resource} = fixture({
    first: action(['second', 'shared', 'unique', 'unique']),
    second: action(['shared']),
  });
  assert.notEqual(CallbackClient.findAction(resource, 'second'), resource.first);
  assert.equal(CallbackClient.findAction(resource, 'unique'), resource.first);
  // Preserve legacy direct-property attachment; safe lookup has its own contract.
  assert.equal(resource.second, resource.first);
  assert.throws(() => CallbackClient.findAction(resource, 'shared'), Client.Exceptions.ProtocolError);
  assert.throws(() => CallbackClient.findAction(resource, 'missing'), Client.Exceptions.ProtocolError);
  assert.throws(() => CallbackClient.findAction(resource, 'toString'), Client.Exceptions.ProtocolError);
});

test('lookup ignores inherited actions and preserves bound IDs and invocation semantics', () => {
  const actions = Object.create({inherited: action()});
  actions.show = action(['fetch']);
  const {client, resource} = fixture(actions);
  assert.throws(() => CallbackClient.findAction(resource, 'inherited'), Client.Exceptions.ProtocolError);
  let sent;
  client.directInvoke = (selected, options) => { sent = {description: selected.description, options}; };
  CallbackClient.findAction(resource(17), 'fetch').directInvoke({params: {count: 0}, onReply() {}});
  assert.equal(sent.description, actions.show);
  assert.equal(sent.options.path, '/mount/v2/widgets/17');
  assert.deepEqual(sent.options.params, {count: 0});
});
