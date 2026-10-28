import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile, mkdir, symlink, access} from 'node:fs/promises';
import {createServer} from 'node:http';
import {dirname, join} from 'node:path';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';

const [directory, runtime] = process.argv.slice(2);
assert.equal(createHash('sha256').update(await readFile(runtime)).digest('hex'),
  '96450c40a55ec7b7af4fca903d045bd0fc7ba1216efe12c3fee9b3e6a09e9198');
const requests = [];
const server = createServer(async (request, response) => {
  try {
    let text = '';
    for await (const chunk of request) text += chunk;
    const url = new URL(request.url, 'http://fixture.invalid');
    const body = text ? JSON.parse(text) : undefined;
    requests.push({method: request.method, url, body, headers: request.headers});
    response.setHeader('Content-Type', 'application/json');
    if (request.method === 'OPTIONS') {
      response.end(JSON.stringify({status: true, version: '2.0', response: {
        authentication: {basic: {}, token: {http_header: 'X-Widget-Token'}},
        meta: {namespace: '_meta'}, resources: {},
      }}));
    } else if (body?.widget?.name === 'reject') {
      response.statusCode = 422;
      response.end(JSON.stringify({status: false, message: 'Fixture rejection', errors: {name: ['Rejected']}, response: {}}));
    } else if (request.method === 'GET' && url.pathname.endsWith('/widgets')) {
      response.end(JSON.stringify({status: true, response: {widgets: [{name: null}], _meta: {count: 1}}}));
    } else {
      response.end(JSON.stringify({status: true, response: {widget: {id: 2, name: null, custom: {opaque: true},
        owner: {key: 2, title: 'Owner'}, 'wire-name': 'raw'}, _meta: {count: 1}}}));
    }
  } catch (error) {
    response.destroy(error);
  }
});

await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
console.log(`http://127.0.0.1:${server.address().port}`);
try {
  const deadline = Date.now() + 60000;
  while (true) {
    try {await access(join(directory, 'ready')); break;} catch {}
    assert.ok(Date.now() < deadline, 'Renderer/compiler did not prepare snippets within 60 seconds');
    await delay(50);
  }
  const modules = join(directory, 'node_modules');
  await mkdir(modules);
  await writeFile(join(directory, 'compiled/generated/package.json'), JSON.stringify({type: 'module', exports: './index.js'}));
  await symlink(join(directory, 'compiled/generated'), join(modules, 'widget-client'));
  await symlink(dirname(dirname(runtime)), join(modules, 'haveapi-client'));
  const cases = JSON.parse(await readFile(join(directory, 'cases.json'), 'utf8'));
  for (const [index, test] of cases.entries()) {
    const previous = requests.length;
    await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [join(directory, `compiled/sample${index}.js`)], {
        stdio: ['ignore', 'pipe', 'pipe'], timeout: 10000,
      });
      let stderr = '';
      child.stderr.on('data', chunk => {stderr += chunk;});
      child.on('error', reject);
      child.on('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`Snippet ${index} ${test.kind} failed (${code}/${signal}): ${stderr}`)));
    });
    const received = requests.slice(previous);
    const auth = test.kind === 'basic' || test.kind === 'token';
    assert.equal(received.length, auth ? 3 : 1, 'Authentication describes twice; application operation sends once');
    for (const request of received.slice(0, -1)) {
      assert.equal(request.method, 'OPTIONS');
      assert.equal(request.url.pathname, `${test.mount}v1.0/`);
      assert.equal(request.url.search, '?describe=default');
    }
    const action = received.at(-1);
    const suffix = test.kind === 'index' ? '/widgets' : test.kind === 'nested' ? '/widgets/1/parts/x%2Fy' : '/widgets/a%2Fb';
    assert.equal(action.url.pathname, `${test.mount}v1.0${suffix}`);
    if (test.kind === 'index') {
      assert.equal(action.method, 'GET');
      assert.deepEqual([...action.url.searchParams], [['custom', ''], ['limit', '0']]);
    } else if (test.kind === 'nested') {
      assert.equal(action.method, 'GET');
    } else {
      assert.equal(action.method, 'PUT');
      assert.equal(action.body.widget.enabled, false);
      assert.equal(action.body.widget.count, 0);
      assert.equal(action.body.widget.cleared, null);
      assert.equal(action.body.widget['wire-name'], 'mapped');
      assert.deepEqual(action.body.widget.custom.__proto__, {kept: true});
      assert.equal(Object.hasOwn(action.body, '_meta'), false);
    }
    if (test.kind === 'basic') assert.equal(action.headers.authorization, `Basic ${Buffer.from('user:secret').toString('base64')}`);
    if (test.kind === 'token') assert.equal(action.headers['x-widget-token'], 'example-token');
  }
  console.log(`Rendered snippets passed public/Basic/existing-token root+mounted wire checks (${cases.length} snippets, ${requests.length} requests)`);
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
