import { AsyncClient, AsyncError, AsyncResourceInstance, AsyncResourceList } from '../../dist/types/haveapi';
import type { InvocationResult, RequestResult, AsyncResource, AsyncAction } from '../../dist/types/haveapi';

const client = new AsyncClient('https://api.example', { language: 'en' });
const setup: Promise<void> = client.setup();
const authenticated: Promise<void> = client.authenticate('token', { token: 'existing' });
const resource: AsyncResource = client.resource('widgets');
const curried: AsyncResource = resource(7).resource('children')(8);
const action: AsyncAction = curried.action('show');
const invocation: Promise<InvocationResult<AsyncResourceInstance>> = action<AsyncResourceInstance>();
const invoked: Promise<InvocationResult<AsyncResourceInstance>> = action.invoke<AsyncResourceInstance>({meta: {includes: 'owner'}});
const read: Promise<RequestResult<{id: number}>> = client.request<{id: number}>({method: 'GET', path: '/widgets/7', outputNamespace: 'widget'});
const created: AsyncResourceInstance = resource.new({label: 'draft'});
created.set('label', 'edited');
const saved: Promise<InvocationResult<AsyncResourceInstance>> = created.save();
const association: Promise<{value: AsyncResourceInstance; response: RequestResult<unknown> | null}> = created.loadAssociation('owner');
const then: undefined = created.then;
const list: AsyncResourceList = null!;
const item: AsyncResourceInstance | undefined = list.itemAt(0);
for (const member of list.items) member.get('label');
const error: AsyncError = new AsyncError('protocol', 'bad response');
const kind: string = error.kind;

// @ts-expect-error Async actions accept options rather than callbacks.
action(7, (client: unknown, result: unknown) => {});
// @ts-expect-error Async options do not include a callback channel.
action({onReply() {}});
// @ts-expect-error The API description does not provide a generated endpoint schema.
client.widgets.show(7);
// @ts-expect-error Async resources do not expose callback object helpers.
created.whenResolved(() => {});
// @ts-expect-error AsyncAction has Promise results, never legacy void returns.
const legacy: void = action();
// @ts-expect-error Returned objects expose a noncallable then.
created.then();

void [setup, authenticated, invocation, invoked, read, saved, association, then, item, kind];
