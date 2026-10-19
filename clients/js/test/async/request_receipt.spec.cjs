const assert = require('node:assert/strict');
const { test } = require('node:test');
const { harness } = require('../helpers/async_bundle.cjs');

for (const scenario of [
  { name: 'selected namespace is absent', payload: { status: true, response: { other: { id: 7 }, _meta: { path_params: [7] } } }, meta: { path_params: [7] } },
  { name: 'payload is absent', payload: { status: true }, meta: {} },
  { name: 'metadata is invalid', payload: { status: true, response: { widget: { id: 7 }, _meta: [] } }, meta: {} },
]) {
  test(`a definite successful envelope retains its raw receipt when ${scenario.name}`, async () => {
    const { HaveAPI, requests } = harness();
    const api = new HaveAPI.AsyncClient('https://api.example');
    const pending = api.request({ method: 'POST', path: '/widgets', outputNamespace: 'widget' });
    const checked = assert.rejects(pending, error => {
      assert.equal(error.kind, 'protocol');
      assert.equal(error.httpStatus, 201);
      assert.equal(error.response.httpStatus, 201);
      assert.equal(error.envelope, error.response.envelope);
      assert.equal(error.response.envelope.status, true);
      assert.deepEqual(JSON.parse(JSON.stringify(error.response.envelope)), scenario.payload);
      assert.equal(error.response.data, error.response.envelope.response);
      assert.deepEqual(JSON.parse(JSON.stringify(error.response.meta)), scenario.meta);
      return true;
    });
    requests[0].respond(scenario.payload, 201); await checked;
  });
}

test('invalid JSON/envelopes and ambiguous transport failures have no validated success receipt', async () => {
  for (const body of ['not json', { status: 'true', response: {} }, { status: true, message: 7, response: {} }]) {
    const { HaveAPI, requests } = harness();
    const api = new HaveAPI.AsyncClient('https://api.example');
    const pending = api.request({ method: 'POST', path: '/widgets', outputNamespace: 'widget' });
    const checked = assert.rejects(pending, error => error.kind === 'protocol' && error.response === undefined && error.envelope === undefined);
    requests[0].respond(body, 201); await checked;
  }
  const { HaveAPI, requests } = harness();
  const api = new HaveAPI.AsyncClient('https://api.example');
  const pending = api.request({ method: 'POST', path: '/widgets', outputNamespace: 'widget' });
  const checked = assert.rejects(pending, error => error.kind === 'transport' && error.response === undefined && error.envelope === undefined);
  requests[0].onerror(); await checked;
});
