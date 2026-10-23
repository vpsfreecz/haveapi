const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {test} = require('node:test');
const rollup = require('rollup');
const {inputOptions} = require('../../rollup.config.js');

const root = path.resolve(__dirname, '../..');

test('the actual Rollup module graph has no runtime cycles or rewritten top-level this', async () => {
  const warnings = [];
  const build = await rollup.rollup({...inputOptions(), onwarn(warning) {
    warnings.push({code: warning.code, message: warning.message});
  }});
  try {
    await build.generate({format: 'iife', name: 'HaveAPI', exports: 'named', strict: false});
  } finally {
    await build.close();
  }
  assert.deepEqual(warnings.filter(warning =>
    warning.code === 'CIRCULAR_DEPENDENCY' || warning.code === 'THIS_IS_UNDEFINED'), []);
});

test('both callback invocation paths use the live original Action completion function', () => {
  const api = require('../../dist/haveapi-client.js');
  const Client = api.CallbackClient;
  assert.equal(Client, api.Client);
  const client = new Client('https://api.example', {version: 1});
  client.useDescription({authentication: {}, meta: {namespace: '_meta'}, resources: {
    widgets: {resources: {}, actions: {run: {
      method: 'POST', path: '/v1/widgets/run', aliases: [], blocking: true,
      input: {layout: 'hash', namespace: 'widget', parameters: {}},
      output: {layout: 'hash', namespace: 'widget', parameters: {}},
    }}},
  }});
  const action = client.widgets.run;
  client._private.http.request = options => options.callback(200, {
    status: true, response: {widget: {}, _meta: {action_state_id: 17}},
  });
  const Action = Client.Action;
  const original = Action.waitForCompletion;
  const calls = [];
  const onDone = () => {};
  try {
    Action.waitForCompletion = options => calls.push(options);
    Client.Action = {waitForCompletion() { assert.fail('replacement constructor used'); }};
    assert.equal(client.directInvoke(action, {path: '/v1/widgets/run', block: true, onDone}), undefined);
    assert.equal(client.invoke(action, {path: '/v1/widgets/run', block: true, onDone}), undefined);
    assert.equal(calls.length, 2);
    for (const call of calls) {
      assert.equal(call.client, client);
      assert.equal(call.id, 17);
      assert.equal(call.onDone, onDone);
      assert.ok(call.reply instanceof Client.Response);
    }
    assert.equal(action.preparedPath, null);
  } finally {
    Client.Action = Action;
    Action.waitForCompletion = original;
  }
});

function temporaryDirectory() {
  const parent = path.join(root, 'test/tmp');
  fs.mkdirSync(parent, {recursive: true});
  return fs.mkdtempSync(path.join(parent, 'module-graph-'));
}

function compile(args) {
  execFileSync(process.execPath, [require.resolve('typescript/bin/tsc'), ...args], {
    cwd: root, encoding: 'utf8', stdio: 'pipe',
  });
}

test('retained async CommonJS facades share class identity and preserve local references and request snapshots', async () => {
  const directory = temporaryDirectory();
  try {
    compile(['-p', 'test/async-resources.tsconfig.json', '--outDir', directory]);
    const emitted = name => require(path.join(directory, 'haveapi/async', name + '.js'));
    const model = emitted('resource_model');
    const resource = emitted('resource');
    const {AsyncResourceInstance} = emitted('resource_instance');
    const {AsyncResourceList} = emitted('resource_list');
    assert.equal(AsyncResourceInstance, model.AsyncResourceInstance);
    assert.equal(AsyncResourceList, model.AsyncResourceList);
    assert.equal(resource.createResource, model.createResource);
    assert.equal(AsyncResourceInstance.name, 'AsyncResourceInstance');
    assert.equal(AsyncResourceList.name, 'AsyncResourceList');

    const output = {layout: 'object', namespace: 'widget', parameters: {}};
    const description = {method: 'POST', path: '/widgets', aliases: [], blocking: false,
      input: {layout: 'object', namespace: 'widget', parameters: {
        owner: {type: 'Resource', value_id: 'id'}, nested: {type: 'Custom'},
      }}, output};
    const requests = [];
    let respond;
    const context = {
      description: {resources: {widgets: {resources: {}, actions: {create: description}},
        owners: {resources: {}, actions: {}}}},
      metaNamespace: '_meta',
      makeError: (kind, message, details) => Object.assign(new Error(message), {kind, ...details}),
      validateParams: (_description, params) => params,
      recordInvocation: (value, response) => ({value, response}),
      request(spec) { requests.push(spec); return new Promise(resolve => { respond = resolve; }); },
    };
    const owner = new AsyncResourceInstance(context, ['owners'], {id: 4}, [4]);
    const draft = resource.createResource(context, ['widgets']).new({owner, nested: {count: 1}});
    assert.equal(draft.get('owner'), owner);
    assert.equal(draft.then, undefined);
    const pending = draft.save();
    owner.set('id', 9);
    draft.get('nested').count = 2;
    assert.equal(requests[0].params.owner, 4);
    assert.equal(requests[0].params.nested.count, 1);
    respond({data: {id: 7}, meta: {path_params: [7]}, envelope: {status: true}, httpStatus: 200});
    assert.equal((await pending).value, draft);
    assert.equal(draft.isPersistent(), true);

    const list = model.materialize(context, ['widgets'], {...description, output: {...output, layout: 'object_list'}},
      {data: [{id: 7}], meta: {total_count: 1}, envelope: {status: true}, httpStatus: 200});
    assert.ok(list instanceof AsyncResourceList);
    assert.ok(list.first() instanceof AsyncResourceInstance);
    assert.equal(Array.from(list)[0], list.itemAt(0));
    assert.equal(list.first(), list.last());
    assert.equal(list.then, undefined);
    assert.throws(() => resource.createResource(context, ['missing']), error => error.kind === 'protocol');
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});

test('public and deep async declarations preserve nominal class and option types', () => {
  const directory = temporaryDirectory();
  try {
    const declarations = path.join(root, 'dist/types/haveapi').replace(/\\/g, '/');
    const consumer = path.join(directory, 'consumer.ts');
    fs.writeFileSync(consumer, `
import {AsyncResourceInstance, AsyncResourceList} from '${declarations}';
import {AsyncResourceInstance as Instance} from '${declarations}/async/resource_instance';
import type {AssociationResult} from '${declarations}/async/resource_instance';
import {AsyncResourceList as List} from '${declarations}/async/resource_list';
import type {AsyncResource, AsyncAction, AsyncActionOptions} from '${declarations}/async/resource';
declare const instance: Instance;
declare const list: List;
declare const resource: AsyncResource;
const publicInstance: AsyncResourceInstance = instance;
const publicList: AsyncResourceList = list;
const association: AssociationResult = {value: publicInstance, response: null};
const options: AsyncActionOptions = {params: {owner: association.value}};
const action: AsyncAction = resource.action('show');
const pending = action(options);
void [publicList, pending];
`);
    const config = path.join(directory, 'tsconfig.json');
    fs.writeFileSync(config, JSON.stringify({
      compilerOptions: {
        strict: true, noEmit: true, target: 'ES2015', module: 'commonjs',
        moduleResolution: 'node', lib: ['ES2015', 'DOM'], types: [],
      },
      files: [consumer],
    }));
    compile(['-p', config]);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
