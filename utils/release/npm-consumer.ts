import { CallbackClient, Client, AsyncClient, AsyncError } from 'haveapi-client';
import type { RequestResult } from 'haveapi-client';

const callback: CallbackClient = new CallbackClient('http://localhost');
const legacy: Client = callback;
const callbackAlias: typeof Client = CallbackClient;
const setup: void = legacy.setup((client, ok) => client.setLanguage(ok ? 'en' : 'cs'));
const asyncClient: AsyncClient = new AsyncClient('http://localhost');
const request: Promise<RequestResult<{ id: number }>> = asyncClient.request({
  method: 'GET', path: '/widgets/1',
});
const error: AsyncError = new AsyncError('protocol', 'Invalid response');

// @ts-expect-error Callback setup still returns void, not a Promise.
const promise: Promise<void> = callback.setup(() => {});
void [callbackAlias, setup, request, error];
