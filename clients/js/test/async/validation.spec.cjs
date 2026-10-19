const assert = require('node:assert/strict');
const { test } = require('node:test');
const { harness, action, description, reply, tick } = require('../helpers/async_bundle.cjs');

const scalarCases = [
  { type: 'Integer', good: 7, bad: ['not-an-int', 1.5, Infinity, {}] },
  { type: 'Float', good: 2.5, bad: ['not-a-float', NaN, Infinity, {}] },
  { type: 'Boolean', good: false, bad: ['not-a-bool', 2, {}, ''] },
  { type: 'Datetime', good: '2026-10-19T12:00:00Z', bad: ['not-a-date', new Date(NaN), {}] },
];

for (const { type, good, bad } of scalarCases) {
  test(`async ${type} validation rejects a later malformed field without sending`, async () => {
    for (const value of bad) {
      const { HaveAPI, requests } = harness();
      const api = new HaveAPI.AsyncClient('https://api.example');
      api.useDescription(description({ a: { type }, b: { type } }));
      const pending = api.resource('widgets').action('validate')({ params: { a: good, b: value } });
      const checked = assert.rejects(pending, error => error.kind === 'validation' &&
        Object.keys(error.errors).join(',') === 'b' && error.errors.b.length > 0);
      // Let the old bug settle too, so the regression fails without hanging.
      if (requests.length) requests[0].respond(reply({}));
      await checked;
      assert.equal(requests.length, 0);
    }
  });
}

test('mixed ordering, missing values and nullable values retain independent coercion', async () => {
  const { HaveAPI, requests } = harness();
  const api = new HaveAPI.AsyncClient('https://api.example');
  api.useDescription(description({ a: { type: 'Integer' }, b: { type: 'Integer' },
    label: { type: 'String' }, omitted: { type: 'Float' }, nullable: { type: 'Boolean', nullable: true } }));
  const pending = api.resource('widgets').action('validate')({ params: {
    b: '8', label: 'between scalar fields', a: '7', omitted: undefined, nullable: ' ',
  } });
  assert.deepEqual(JSON.parse(requests[0].body).widget,
    { b: 8, label: 'between scalar fields', a: 7, nullable: null });
  requests[0].respond(reply({})); await pending;
  await assert.rejects(api.resource('widgets').action('validate')({ params: { b: 'bad', a: 7 } }),
    error => error.kind === 'validation' && Array.isArray(error.errors.b));
  assert.equal(requests.length, 1);
});

test('validators run once with all coerced siblings and accumulate field errors', async () => {
  const { HaveAPI, requests } = harness();
  const api = new HaveAPI.AsyncClient('https://api.example');
  api.useDescription(description({
    a: { type: 'Integer', validators: { confirm: { parameter: 'b', equal: true, message: 'must match b' } } },
    b: { type: 'Integer', validators: { present: { message: 'required' } } },
  }));
  const valid = api.resource('widgets').action('validate')({ params: { a: '7', b: 7 } });
  assert.deepEqual(JSON.parse(requests[0].body).widget, { a: 7, b: 7 });
  requests[0].respond(reply({})); await valid;
  await assert.rejects(api.resource('widgets').action('validate')({ params: { a: 7, b: 8 } }),
    error => error.kind === 'validation' && error.errors.a[0] === 'must match b');
  await assert.rejects(api.resource('widgets').action('validate')({ params: { a: 7 } }),
    error => error.kind === 'validation' && Array.isArray(error.errors.b));
  await assert.rejects(api.resource('widgets').action('validate')({ params: { a: 'bad', b: 'bad' } }),
    error => error.kind === 'validation' && Object.keys(error.errors).sort().join(',') === 'a,b');
  assert.equal(requests.length, 1);
});

test('MFA challenge answers use the real shared validator before challenge HTTP', async () => {
  const { HaveAPI, requests } = harness();
  const api = new HaveAPI.AsyncClient('https://api.example');
  const doc = description();
  doc.authentication.token = { http_header: 'X-Token', resources: { token: { resources: {}, actions: {
    request: action({ lifetime: { type: 'String' } }, { path: '/v1/token/request',
      input: { layout: 'hash', namespace: 'token', parameters: { lifetime: { type: 'String' } } },
      output: { layout: 'hash', namespace: 'token', parameters: {} } }),
    challenge: action(null, { path: '/v1/token/challenge',
      input: { layout: 'hash', namespace: 'token', parameters: {
        token: { type: 'String' }, a: { type: 'Integer' }, b: { type: 'Integer' },
      } }, output: { layout: 'hash', namespace: 'token', parameters: {} } }),
  } } } };
  api.useDescription(doc);
  const answer = Object.assign(Object.create(null), { a: 7, b: 'not-an-int' });
  const pending = api.authenticate('token', { onChallenge: () => answer });
  const checked = assert.rejects(pending, error => error.kind === 'validation' && Array.isArray(error.errors.b));
  await tick(); assert.equal(requests.length, 1);
  requests[0].respond(reply({ complete: false, token: 'temporary', next_action: 'challenge' }, 'token'));
  await tick();
  if (requests.length > 1) requests[1].respond({ status: false, message: 'unexpected challenge send' }, 400);
  await checked;
  assert.equal(requests.length, 1);
  assert.deepEqual(Object.keys(answer), ['a', 'b']);
  assert.equal(answer.b, 'not-an-int');
});

test('default callback Parameters retains its existing coercion and instance shape', () => {
  const { HaveAPI } = harness();
  for (const { type, good, bad } of scalarCases) {
    const client = new HaveAPI.Client('https://api.example');
    client.useDescription(description({ a: { type }, b: { type } }));
    const prepared = client.widgets.validate.prepareInvoke([{ a: good, b: bad[0] }]).params;
    assert.equal(prepared.constructor.length, 2);
    assert.equal(prepared.validate(), true);
    assert.equal(prepared.params.b, good);
    assert.equal(Object.hasOwn(prepared, '_dictionaryPolicy'), false);
  }
});
