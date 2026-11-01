import {createClient} from './generated/index.js';
import {ClientInputError} from './generated/index.js';
import type {ActionResult, ApiDescription, ActionDescription, RequestExecutor} from './generated/index.js';
import type {Widget__UpdateOutput, Widget__IndexOutput, Widget__HashesOutput} from './generated/index.js';
import {AsyncClient} from 'haveapi-client';
import {createClient as createLegacyClient, API_VERSION} from './generated/api.js';
import type {WidgetResource as LegacyWidgetResource, Widget__UpdateOptions as LegacyUpdateOptions} from './generated/api.js';
import {createAction as bindUpdate} from './generated/resources/widget/actions/update.js';
import type {Widget__UpdateOptions} from './generated/resources/widget/actions/update.js';
import type {WidgetResource} from './generated/resources/widget/resource.js';
import type {Widget__Part__ShowOptions} from './generated/resources/widget/resources/part/actions/show.js';
// @ts-expect-error internal action binders are not part of the public root
import {createAction} from './generated/index.js';
// @ts-expect-error internal resource factories are not part of the legacy API barrel
import {createResource} from './generated/api.js';

const runtime = new AsyncClient('https://api.example/mount/v1.0');
const execute: RequestExecutor = spec => runtime.request(spec);
const client = createClient({execute});
const legacy: LegacyWidgetResource = createLegacyClient({execute}).widget;
const resource: WidgetResource = legacy;
const options: Widget__UpdateOptions = {path: {widget_id: 1}, params: {name: 'direct'}};
const legacyOptions: LegacyUpdateOptions = options;
const nestedOptions: Widget__Part__ShowOptions = {path: {widget_id: 1, part_id: 2}};
bindUpdate(execute)(legacyOptions);
resource.part.show(nestedOptions);
void API_VERSION;

client.widget.update({path: {widget_id: 1}, params: {name: '', enabled: false, count: 0, cleared: null, optional: undefined}});
client.widget.change({path: {widget_id: 'a/b'}, params: {name: 'new', custom: {list: [false, 0, null]}}});
client.widget.update({path: {widget_id: 1}, params: {name: 'ok', wire_name: 'wire', _meta: {revision: 1}}});
client.widget.update({path: {widget_id: 1}, params: {name: 'ok', _meta: undefined}});
client.widget.index();
client.widget.index({params: {custom: null}, meta: {notify: false}, timeoutMs: 100, signal: new AbortController().signal});
client.widget.empty();
client.widget.audit({meta: {token: 'required'}});
client.widget.object_only({params: {_meta: {revision: 2}}});
client.widget.hashes();
client.widget.part.show({path: {widget_id: 1, part_id: 2}});

// @ts-expect-error unknown resources are not generated
client.missing.index();
// @ts-expect-error unknown actions are not generated
client.widget.missing();
// @ts-expect-error required options cannot be omitted
client.widget.update();
// @ts-expect-error required path cannot be omitted
client.widget.update({params: {name: 'new'}});
// @ts-expect-error required input cannot be omitted
client.widget.update({path: {widget_id: 1}});
// @ts-expect-error required field cannot be omitted
client.widget.update({path: {widget_id: 1}, params: {enabled: true}});
// @ts-expect-error non-nullable input cannot be cleared
client.widget.update({path: {widget_id: 1}, params: {name: null}});
// @ts-expect-error integer input uses a number, without coercion
client.widget.index({params: {limit: '10'}});
// @ts-expect-error structured query Custom cannot be encoded by HaveAPI 0.32.0
client.widget.index({params: {custom: {unsafe: true}}});
// @ts-expect-error unversioned auth operations remain with the runtime
client.authentication.token.request();
// @ts-expect-error paths do not accept boolean values
client.widget.part.show({path: {widget_id: true, part_id: 2}});
// @ts-expect-error global metadata can require options even without input
client.widget.audit();
// @ts-expect-error required object metadata makes the params object required
client.widget.object_only();
// @ts-expect-error the object metadata field cannot be omitted
client.widget.object_only({params: {}});
// @ts-expect-error no-input actions reject params
client.widget.empty({params: {name: 'unexpected'}});
// @ts-expect-error custom JSON excludes undefined
client.widget.update({path: {widget_id: 1}, params: {name: 'new', custom: {bad: undefined}}});

const output: Widget__UpdateOutput = {};
const name: string | null | undefined = output.name;
const originalWireName: string | null | undefined = output['wire-name'];
// @ts-expect-error raw DTO output keys are not renamed
output.wire_name;
// @ts-expect-error response fields may be filtered or null
const guaranteedName: string = output.name;
const list: Widget__IndexOutput = [{name: null, _meta: {revision: null}}];
const hashes: Widget__HashesOutput = [{name: null}];
// @ts-expect-error Custom output needs consumer validation before use
const customString: string = output.custom;
void [name, originalWireName, guaranteedName, list, hashes, customString];

const described: Promise<ActionResult<ApiDescription>> = client.describe();
const capability: Promise<ActionResult<ActionDescription>> = client.widget.update.describe({path: {widget_id: 1}});
client.widget.change.describe({path: {widget_id: 'alias'}, headers: {'X-Test': 'test'}, timeoutMs: 100});
client.widget.index.describe();
client.widget.audit.describe(); // required mutation input is irrelevant to OPTIONS
const customNamespace = createClient({execute, metaNamespace: 'wire_meta'});
customNamespace.widget.object_only({params: {_meta: {revision: 0}}});
// @ts-expect-error metadata inputs retain the schema-named key, not wire override keys
customNamespace.widget.object_only({params: {wire_meta: {revision: 0}}});
// @ts-expect-error description options cannot inject arbitrary HTTP paths
client.describe({path: '/anything'});
// @ts-expect-error action descriptions require their concrete resource IDs
client.widget.update.describe();
// @ts-expect-error an action description does not accept mutation params
client.widget.update.describe({path: {widget_id: 1}, params: {name: 'no write'}});
// @ts-expect-error nested descriptions require every path placeholder
client.widget.part.show.describe({path: {widget_id: 1}});
client.widget.update({path: {widget_id: 1}, params: {name: 'typed'}}).then(result => {
  const count: number | null | undefined = result.meta.count;
  const extension: unknown = result.meta['new_server_field'];
  // @ts-expect-error emitted metadata fields retain their actual primitive type
  const wrong: string = result.meta.count;
  void [count, extension, wrong];
});
client.widget.empty().then(result => {
  const extension: unknown = result.meta['new_server_field'];
  // @ts-expect-error an extension to empty known metadata is unknown, not never
  const guaranteed: number = result.meta['new_server_field'];
  void [extension, guaranteed];
});
capability.then(result => {
  const required: boolean | null | undefined = result.data.input?.parameters?.['name']?.required;
  const unknownField: unknown = result.data['future_extension'];
  void [required, unknownField];
});
const inputFailure = new ClientInputError('input rejected');
const discriminant: 'HAVEAPI_CLIENT_INPUT_ERROR' = inputFailure.code;
const phase: 'pre-dispatch' = inputFailure.phase;
void [described, capability, discriminant, phase];
