import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';

const {createClient, ClientInputError} = await import(pathToFileURL(process.argv[2]).href);
const calls = [];
const data = {name: null, 'wire-name': 'raw', custom: {unvalidated: true}};
const meta = {count: 3};
const envelope = {status: true, response: {widget: data, _meta: meta}};
const receipt = {data, meta, envelope, httpStatus: 201};
const client = createClient({execute: async spec => {calls.push(spec); return receipt;}});
assert.equal(client.widget.update, client.widget.change, 'aliases reuse the canonical bound function');
const signal = new AbortController().signal;
const headers = {'X-Auth': 'test-only'};
const result = await client.widget.update({
  path: {widget_id: 'a/b ?#%ü'},
  params: {name: '', enabled: false, count: 0, cleared: null, optional: undefined,
    wire_name: 'original', custom: {array: [false, 0, null]}, _meta: {revision: 4}},
  meta: {notify: false}, headers, signal, timeoutMs: 500,
});
assert.equal(calls.length, 1);
assert.deepEqual({...calls[0]}, {
  method: 'PUT', path: '/widgets/a%2Fb%20%3F%23%25%C3%BC',
  inputNamespace: 'widget', outputNamespace: 'widget', metaNamespace: '_meta',
  params: calls[0].params, meta: calls[0].meta, headers, signal, timeoutMs: 500,
});
assert.deepEqual({...calls[0].params}, {
  name: '', enabled: false, count: 0, cleared: null, 'wire-name': 'original',
  custom: {array: [false, 0, null]}, _meta: calls[0].params._meta,
});
assert.deepEqual({...calls[0].params._meta}, {revision: 4});
assert.deepEqual({...calls[0].meta}, {notify: false});
assert.equal(result.data, data);
assert.equal(result.meta, meta);
assert.equal(result.envelope, envelope);
assert.equal(result.httpStatus, 201);
assert.equal(result.data.wire_name, undefined);
// The exact already-versioned mounted runtime base composes without duplication.
assert.equal(new URL('https://api.example/mount/v1.0' + calls[0].path).href,
  'https://api.example/mount/v1.0/widgets/a%2Fb%20%3F%23%25%C3%BC');

await client.widget.index();
assert.equal(calls.at(-1).inputNamespace, null);
assert.equal(calls.at(-1).outputNamespace, 'widgets');
assert.equal(Object.hasOwn(calls.at(-1), 'params'), false);
assert.equal(Object.hasOwn(calls.at(-1), 'meta'), false);
await client.widget.index({params: {limit: 0, custom: null}});
assert.deepEqual({...calls.at(-1).params}, {limit: 0, custom: null});
await client.widget.change({path: {widget_id: 42}, params: {name: 'alias'}});
assert.equal(calls.at(-1).path, '/widgets/42');
await client.widget.part.show({path: {widget_id: 1, part_id: 'x/y'}});
assert.equal(calls.at(-1).path, '/widgets/1/parts/x%2Fy');
await client.widget.empty();
assert.equal(Object.hasOwn(calls.at(-1), 'params'), false);
await client.widget.audit({meta: {token: 'required'}});
await client.widget.object_only({params: {_meta: {revision: 2}}});
assert.equal(calls.at(-1).inputNamespace, null);
assert.deepEqual({...calls.at(-1).params._meta}, {revision: 2});
await client.widget.hashes();
assert.equal(calls.at(-1).outputNamespace, 'hashes');

const invalid = [
  () => client.widget.update(),
  () => client.widget.update({path: {widget_id: 1}, params: {}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: null}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', count: Number.MAX_SAFE_INTEGER + 1}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', owner: 1.5}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', ratio: Infinity}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', enabled: 0}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', custom: new Date()}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', custom: {bad: undefined}}}),
  () => client.widget.update({path: {widget_id: Number.MAX_SAFE_INTEGER + 1}, params: {name: 'ok'}}),
  () => client.widget.update({path: {widget_id: '..'}, params: {name: 'ok'}}),
  () => client.widget.update({path: {widget_id: '.'}, params: {name: 'ok'}}),
  () => client.widget.update({path: {widget_id: ''}, params: {name: 'ok'}}),
  () => client.widget.update({path: {widget_id: 1, extra: 2}, params: {name: 'ok'}}),
  () => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', unknown: 1}}),
  () => client.widget.index({params: {custom: {structured: true}}}),
  () => client.widget.audit(),
  () => client.widget.object_only(),
  () => client.widget.object_only({params: {}}),
  () => client.widget.empty({params: {unexpected: 'input'}}),
];
for (const invoke of invalid) {
  const previous = calls.length;
  await assert.rejects(invoke, error => {
    assert.ok(error instanceof TypeError && error instanceof ClientInputError);
    assert.equal(error.code, 'HAVEAPI_CLIENT_INPUT_ERROR');
    assert.equal(error.phase, 'pre-dispatch');
    assert.equal(Object.hasOwn(error, 'params'), false);
    return true;
  });
  assert.equal(calls.length, previous, 'invalid input must reject before sending');
}
const inherited = Object.create({name: 'inherited'});
await assert.rejects(() => client.widget.update({path: {widget_id: 1}, params: inherited}), /Missing required/);
const cycle = {};
cycle.self = cycle;
await assert.rejects(() => client.widget.update({path: {widget_id: 1}, params: {name: 'ok', custom: cycle}}), /Invalid JSON/);

const descriptions = [];
const descriptionData = {input: {parameters: {name: {required: true}}}, extra: 'extension'};
const descriptionReceipt = {data: descriptionData, meta: {future: false}, envelope: {status: true, response: descriptionData}, httpStatus: 200};
const described = createClient({execute: async spec => {descriptions.push(spec); return descriptionReceipt;}});
assert.equal(await described.describe({headers, signal, timeoutMs: 25}), descriptionReceipt);
assert.deepEqual(descriptions.at(-1), {
  method: 'OPTIONS', path: '/', inputNamespace: null, outputNamespace: null, metaNamespace: '_meta', headers, signal, timeoutMs: 25,
});
await described.widget.change.describe({path: {widget_id: 'a/b'}, signal});
assert.equal(descriptions.at(-1).path, '/widget-help/a%2Fb?method=PUT', 'uses explicit recorded help, not guessed operation route');
assert.equal(new URL('https://api.example/mount/v1.0' + descriptions.at(-1).path).pathname, '/mount/v1.0/widget-help/a%2Fb');
await described.widget.part.show.describe({path: {widget_id: 1, part_id: 'nested/ID'}});
assert.equal(descriptions.at(-1).path, '/widgets/1/parts/nested%2FID?method=GET');
await described.widget.audit.describe();
const beforeInvalidDescription = descriptions.length;
for (const invoke of [
  () => described.describe({path: '/injected'}),
  () => described.widget.update.describe(),
  () => described.widget.update.describe({path: {widget_id: '\ud800'}}),
  () => described.widget.update.describe({path: {widget_id: 1}, params: {name: 'secret-value'}}),
]) await assert.rejects(invoke, ClientInputError);
assert.equal(descriptions.length, beforeInvalidDescription);
// Payload validation remains with consumers. The generator preserves a malformed
// description receipt and the executor's denied/protocol error without rewriting.
const malformed = {data: null, meta: {}, envelope: {status: true, response: null}, httpStatus: 200};
assert.equal(await createClient({execute: async () => malformed}).describe(), malformed);

const namespaceCalls = [];
const customRows = [{name: 'wire', custom: {_meta: {keep: true}}, wire_meta: {revision: 0}}];
const customEnvelope = {status: true, response: {widgets: customRows, wire_meta: {count: 0, extension: null}}};
const customClient = createClient({metaNamespace: 'wire_meta', execute: async spec => {
  namespaceCalls.push(spec);
  return {data: customRows, meta: customEnvelope.response.wire_meta, envelope: customEnvelope, httpStatus: 200};
}});
await customClient.widget.update({path: {widget_id: 1}, params: {name: 'custom', _meta: {revision: 0}}, meta: {notify: false}});
assert.deepEqual({...namespaceCalls.at(-1).params.wire_meta}, {revision: 0});
assert.equal(Object.hasOwn(namespaceCalls.at(-1).params, '_meta'), false);
assert.deepEqual({...namespaceCalls.at(-1).meta}, {notify: false});
assert.equal(namespaceCalls.at(-1).metaNamespace, 'wire_meta');
const customResult = await customClient.widget.index();
assert.equal(customResult.data[0]._meta, customRows[0].wire_meta);
assert.equal(customResult.data[0].custom, customRows[0].custom, 'Custom output is not traversed');
assert.equal(customResult.envelope, customEnvelope);
assert.equal(Object.hasOwn(customRows[0], '_meta'), false, 'raw envelope data stays untouched');
assert.equal(customResult.meta, customEnvelope.response.wire_meta);
await customClient.describe();
assert.equal(namespaceCalls.at(-1).metaNamespace, 'wire_meta');
await customClient.widget.index.describe();
assert.equal(namespaceCalls.at(-1).metaNamespace, 'wire_meta');
for (const metaNamespace of ['', null, '__proto__', 'name', 'widget', 'widgets', 'output-only']) {
  assert.throws(() => createClient({metaNamespace, execute: async () => receipt}), ClientInputError);
}

const failure = new Error('executor retains uncertain-write semantics');
let attempts = 0;
const failing = createClient({execute: async () => {attempts++; throw failure;}});
await assert.rejects(() => failing.widget.update({path: {widget_id: 1}, params: {name: 'ok'}}), error => error === failure);
assert.equal(attempts, 1, 'mutations are never replayed');
const transportFailure = new TypeError('transport uncertainty');
const transport = createClient({execute: async () => {throw transportFailure;}});
await assert.rejects(() => transport.widget.update({path: {widget_id: 1}, params: {name: 'ok'}}), error => error === transportFailure && !(error instanceof ClientInputError));
await assert.rejects(() => transport.widget.update.describe({path: {widget_id: 1}}), error => error === transportFailure);
console.log('generated strict types and runtime spy contract passed');
