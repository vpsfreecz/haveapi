// Compile against emitted package declarations, never the authored TS modules.
import { Client } from '../../dist/types/haveapi';
import type { Action, ActionReply } from '../../dist/types/haveapi/action';
import type { Resource } from '../../dist/types/haveapi/resource';
import type { ResourceInstance } from '../../dist/types/haveapi/resource_instance';
import type { Response } from '../../dist/types/haveapi/response';
import type { ResourceDescription, ActionDescription } from '../../dist/types/haveapi/types';

const client = new Client('https://api.example', { language: 'cs', version: '1.0' });
const actionDescription: ActionDescription = {
  method: 'GET', path: '/v1/widgets/{widget_id}', aliases: ['get'],
  input: { layout: 'hash', namespace: 'widget', parameters: {} },
  output: { layout: 'object', namespace: 'widget', parameters: {} },
};
const resourceDescription: ResourceDescription = {
  resources: {}, actions: { show: actionDescription },
};
const resource = new Client.Resource(client, null, 'widgets', resourceDescription, []);
const bound: Resource = resource(7);
const action = new Client.Action(client, bound, 'show', actionDescription);

const setupReturn: void = client.setup((owner, status) => {
  const sameClient: Client = owner;
  const succeeded: boolean = status;
  sameClient.setLanguage(succeeded ? 'cs' : 'en');
});
client.authenticate('basic', { user: 'alice', password: 'secret' }, (owner, status) => {
  owner.setLanguage(status ? 'en' : 'cs');
}, false);
client.logout();
client.availableVersions((owner, status, versions) => {
  if (status && versions) owner.setLanguage(String(versions.default));
});

const callback = (owner: Client, result: ActionReply): void => {
  owner.setLanguage(result.isOk() ? 'en' : 'cs');
};
const noReply: void = action(7);
const oldParamsNoReply: void = action(7, { limit: 2 });
const oldCallback: void = action(7, callback);
const oldParams: void = action(7, { limit: 2, meta: { count: true } }, callback);
const options: void = action.invoke(7, {
  params: { limit: 2 }, meta: { count: true },
  onReply(owner, result) { callback(owner, result); },
  onStateChange(owner, result, state) {
    callback(owner, result);
    const current: number | undefined = state.progress.current;
    if (current) state.stop();
  },
  onDone: callback,
});
action.directInvoke(7, (owner, raw) => {
  const response: Response = raw;
  owner.setLanguage(response.meta().language === 'cs' ? 'cs' : 'en');
});

// Application-authored endpoint types can narrow a known response without
// pretending arbitrary description names were statically generated.
const typed: Action<Response<{ id: number }>> = new Client.Action(client, bound, 'show', actionDescription);
typed(7, (owner, response) => {
  const id: number | undefined = response.response()?.id;
  if (id) owner.setLanguage('en');
});

const instance: ResourceInstance = resource.new();
instance.save((owner, saved) => {
  const sameInstance: ResourceInstance = saved;
  owner.setLanguage(sameInstance.isOk() ? 'cs' : 'en');
});
instance.whenResolved((owner, resolved) => { owner.setLanguage(resolved.getName()); });

// @ts-expect-error The legacy callback API must not be typed as a Promise.
const promise: Promise<unknown> = action(7, callback);
// @ts-expect-error setup still requires its legacy callback.
client.setup();
// @ts-expect-error Callback status is a boolean, not a Promise result wrapper.
client.setup((owner: Client, status: string) => {});
// @ts-expect-error A described endpoint is unknown until a schema is supplied.
client.widgets.show(7);
// @ts-expect-error Callable resources are not a permissive endpoint index.
resource.missingAction();
// @ts-expect-error directInvoke returns the raw Response wrapper.
action.directInvoke(7, (owner: Client, raw: ResourceInstance) => {});

void [setupReturn, noReply, oldParamsNoReply, oldCallback, oldParams, options];
