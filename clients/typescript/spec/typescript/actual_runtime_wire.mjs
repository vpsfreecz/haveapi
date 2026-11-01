import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

const [generated, runtimeFile] = process.argv.slice(2);
// Exact bundle from the published npm haveapi-client@0.32.0 tarball. The test
// accepts a prepared installation and never downloads or vendors a runtime.
assert.equal(createHash('sha256').update(await readFile(runtimeFile)).digest('hex'),
  '9285eab56e435ee86a501a24808e15496d44521881a032090003a1108511f016');
const {AsyncClient, AsyncError} = createRequire(import.meta.url)(runtimeFile);
const {createClient} = await import(pathToFileURL(generated).href);
const received = [];
let observedSlow;
let slowResponse;
const slowRequest = new Promise(resolve => {observedSlow = resolve;});
const server = createServer(async (request, response) => {
  let text = '';
  for await (const chunk of request) text += chunk;
  const url = new URL(request.url, 'http://fixture.invalid');
  received.push({method: request.method, url, body: text ? JSON.parse(text) : undefined, headers: request.headers});
  if (url.pathname.endsWith('/widgets/slow')) {
    slowResponse = response;
    observedSlow();
    return;
  }
  response.setHeader('Content-Type', 'application/json');
  const metaNamespace = request.headers['x-meta-namespace'] || '_meta';
  if (request.method === 'OPTIONS') {
    if (url.pathname.endsWith('/widget-help/denied')) {
      response.statusCode = 403;
      response.end(JSON.stringify({status: false, message: 'description denied', response: null}));
    } else if (url.pathname.endsWith('/widget-help/malformed')) {
      response.end('{not JSON');
    } else {
      response.end(JSON.stringify({status: true, version: '2.0', response: {
        authentication: {}, resources: {}, meta: {namespace: metaNamespace},
        input: {parameters: {name: {type: 'String', required: true, nullable: false}}},
      }}));
    }
  } else if (url.pathname.endsWith('/widgets/empty')) {
    response.statusCode = 422;
    response.end(JSON.stringify({status: false, message: 'fixture rejection', errors: {name: ['rejected']}, response: {}}));
  } else if (url.searchParams.get('custom') === 'missing') {
    response.end(JSON.stringify({status: true, response: {_meta: {count: 0}}}));
  } else if (request.method === 'GET') {
    response.end(JSON.stringify({status: true, response: {widgets: [{name: null, [metaNamespace]: {revision: 2}}], [metaNamespace]: {count: 1}}}));
  } else {
    response.end(JSON.stringify({status: true, response: {widget: {id: 9, name: null}, [metaNamespace]: {count: 1}}}));
  }
});

await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  const base = `http://127.0.0.1:${server.address().port}/mount/v1.0`;
  const runtime = new AsyncClient(base, {language: 'en'});
  const client = createClient({execute: spec => runtime.request(spec)});
  const timeoutMs = 5000;
  const write = await client.widget.update({
    path: {widget_id: 9},
    params: {name: '', enabled: false, count: 0, cleared: null, optional: undefined, wire_name: 'exact', _meta: {revision: 2}},
    meta: {notify: false}, headers: {'X-Fixture': 'prepared-runtime'}, timeoutMs,
  });
  assert.equal(received.length, 1);
  assert.equal(received[0].url.pathname, '/mount/v1.0/widgets/9');
  assert.deepEqual(received[0].body, {
    widget: {name: '', enabled: false, count: 0, cleared: null, 'wire-name': 'exact', _meta: {revision: 2}},
    _meta: {notify: false},
  });
  assert.equal(received[0].headers['x-fixture'], 'prepared-runtime');
  assert.equal(write.data.name, null);
  assert.equal(Object.hasOwn(write.data, 'count'), false);
  assert.equal(write.data, write.envelope.response.widget);
  assert.equal(write.meta, write.envelope.response._meta);
  assert.equal(write.httpStatus, 200);

  const list = await client.widget.index({params: {limit: 0, custom: null}, meta: {notify: false}, timeoutMs});
  assert.equal(received.length, 2);
  assert.equal(received[1].url.pathname, '/mount/v1.0/widgets');
  assert.deepEqual([...received[1].url.searchParams].sort(), [['_meta[notify]', 'false'], ['custom', ''], ['limit', '0']]);
  assert.deepEqual(list.data, [{name: null, _meta: {revision: 2}}]);
  assert.deepEqual(list.meta, {count: 1});
  assert.equal(list.data, list.envelope.response.widgets);

  await assert.rejects(() => client.widget.empty({timeoutMs}), error => {
    assert.ok(error instanceof AsyncError);
    assert.equal(error.kind, 'api');
    assert.equal(error.httpStatus, 422);
    assert.deepEqual(error.errors, {name: ['rejected']});
    assert.equal(error.response.envelope, error.envelope);
    return true;
  });
  await assert.rejects(() => client.widget.index({params: {custom: 'missing'}, timeoutMs}), error => {
    assert.equal(error.kind, 'protocol');
    assert.equal(error.response.envelope, error.envelope);
    return true;
  });
  assert.equal(received.length, 4, 'errors must not replay requests');

  const root = await client.describe({timeoutMs});
  assert.equal(received.at(-1).url.pathname, '/mount/v1.0/');
  assert.equal(received.at(-1).method, 'OPTIONS');
  assert.equal(root.data.meta.namespace, '_meta');
  assert.equal(root.data, root.envelope.response);
  const capability = await client.widget.update.describe({path: {widget_id: 'a/b'}, timeoutMs});
  assert.equal(received.at(-1).url.pathname, '/mount/v1.0/widget-help/a%2Fb');
  assert.equal(received.at(-1).url.search, '?method=PUT');
  assert.equal(capability.data.input.parameters.name.required, true);
  for (const [widget_id, kind] of [['denied', 'api'], ['malformed', 'protocol']]) {
    const previous = received.length;
    await assert.rejects(() => client.widget.update.describe({path: {widget_id}, timeoutMs}), error => error instanceof AsyncError && error.kind === kind);
    assert.equal(received.length, previous + 1, 'description errors do not retry');
  }
  const custom = createClient({execute: spec => runtime.request(spec), metaNamespace: 'wire_meta'});
  const namespaceHeaders = {'X-Meta-Namespace': 'wire_meta'};
  await custom.widget.update({path: {widget_id: 9}, params: {name: 'custom', _meta: {revision: 0}}, meta: {notify: false}, headers: namespaceHeaders, timeoutMs});
  assert.deepEqual(received.at(-1).body, {widget: {name: 'custom', wire_meta: {revision: 0}}, wire_meta: {notify: false}});
  const customList = await custom.widget.index({meta: {notify: false}, headers: namespaceHeaders, timeoutMs});
  assert.equal(received.at(-1).url.searchParams.get('wire_meta[notify]'), 'false');
  assert.equal(customList.data[0]._meta.revision, 2);
  assert.equal(customList.envelope.response.widgets[0]._meta, undefined);
  assert.equal(customList.envelope.response.widgets[0].wire_meta.revision, 2);
  assert.equal(customList.meta.count, 1);

  const controller = new AbortController();
  const pending = client.widget.update({path: {widget_id: 'slow'}, params: {name: 'accepted-or-uncertain'}, signal: controller.signal, timeoutMs});
  const rejected = assert.rejects(pending, error => error instanceof AsyncError && error.kind === 'aborted');
  await Promise.race([slowRequest, pending.then(() => {throw new Error('Slow write unexpectedly completed');})]);
  controller.abort();
  await rejected;
  assert.equal(received.length, 11, 'aborting a write must not replay it');
  // Observation abort does not prove whether the server accepted the write.
  console.log('published 0.32.0 AsyncClient wire integration passed (11 single sends)');
} finally {
  if (slowResponse) slowResponse.destroy();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
