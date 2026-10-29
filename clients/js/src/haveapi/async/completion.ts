import { AsyncError, asAsyncError } from "./error";
import { isRecord, own } from "./request";
import type { ActionDescription, IdArgument } from "../types";
import type {
  ActionStateSnapshot,
  AsyncResourceContext,
  CompletionOptions,
  CompletionResult,
  InvocationResult,
} from "./types";

export interface InvocationRecord {
  context: AsyncResourceContext;
  action: ActionDescription;
  stateId: unknown;
}
function stateSnapshot(data: unknown): ActionStateSnapshot {
  if (
    !isRecord(data) ||
    typeof data.id !== "number" ||
    !Number.isInteger(data.id) ||
    typeof data.finished !== "boolean" ||
    typeof data.status !== "boolean" ||
    typeof data.current !== "number" ||
    !Number.isFinite(data.current) ||
    typeof data.total !== "number" ||
    !Number.isFinite(data.total) ||
    typeof data.can_cancel !== "boolean"
  )
    throw new AsyncError("protocol", "Invalid action state");
  return {
    id: data.id,
    finished: data.finished,
    status: data.status,
    canCancel: data.can_cancel,
    ...(typeof data.label === "string" ? { label: data.label } : {}),
    progress: {
      current: data.current,
      total: data.total,
      ...(typeof data.unit === "string" ? { unit: data.unit } : {}),
    },
    ...(typeof data.created_at === "string" || data.created_at === null
      ? { createdAt: data.created_at }
      : {}),
    ...(typeof data.updated_at === "string" || data.updated_at === null
      ? { updatedAt: data.updated_at }
      : {}),
  };
}
function actionPath(action: ActionDescription, id: IdArgument): string {
  let remaining = true;
  const path = action.path.replace(/\{[a-zA-Z0-9_-]+\}/g, () => {
    if (!remaining)
      throw new AsyncError("protocol", "Unresolved action-state path");
    remaining = false;
    return encodeURIComponent(String(id));
  });
  return path;
}
export async function waitForCompletion<T>(
  result: InvocationResult<T>,
  record: InvocationRecord | undefined,
  options: CompletionOptions,
): Promise<CompletionResult<T>> {
  if (!record) throw new AsyncError("protocol", "Unknown action invocation");
  if (
    !record.action.blocking ||
    record.stateId === undefined ||
    record.stateId === null
  )
    return { value: result.value, response: result.response, state: null };
  if (!options || !Number.isFinite(options.timeoutMs) || options.timeoutMs <= 0)
    throw new AsyncError("validation", "Completion timeout must be positive", {
      response: result.response,
    });
  if (
    typeof record.stateId !== "number" ||
    !Number.isInteger(record.stateId) ||
    record.stateId < 0
  )
    throw new AsyncError("protocol", "Invalid action-state identifier", {
      response: result.response,
    });
  const resources = record.context.description.resources;
  const resource = own(resources, "action_state")
    ? resources.action_state
    : undefined;
  if (
    !resource ||
    !own(resource.actions, "show") ||
    !own(resource.actions, "poll")
  )
    throw new AsyncError("protocol", "Missing action-state resource", {
      response: result.response,
    });
  const controller = new AbortController();
  let timedOut = false;
  let state: ActionStateSnapshot | undefined;
  const abort = () => controller.abort();
  if (options.signal) {
    options.signal.addEventListener("abort", abort);
    if (options.signal.aborted) abort();
  }
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, options.timeoutMs);
  const started = Date.now();
  try {
    let action = resource.actions.show;
    for (;;) {
      const remaining = options.timeoutMs - (Date.now() - started);
      if (remaining <= 0)
        throw new AsyncError("timeout", "Completion wait timed out");
      if (controller.signal.aborted)
        throw new AsyncError(
          timedOut ? "timeout" : "aborted",
          "Completion wait stopped",
        );
      const params = state
        ? {
            timeout: Math.min(
              options.blockInterval === undefined ? 15 : options.blockInterval,
              remaining / 1000,
              30,
            ),
            update_in:
              options.blockUpdateIn === undefined ? 3 : options.blockUpdateIn,
            current: state.progress.current,
            total: state.progress.total,
            status: state.status,
          }
        : undefined;
      const reply = await record.context.request({
        method: action.method,
        path: actionPath(action, record.stateId),
        inputNamespace: action.input && action.input.namespace,
        outputNamespace: action.output && action.output.namespace,
        params: record.context.validateParams(action, params),
        signal: controller.signal,
        timeoutMs: remaining,
      });
      state = stateSnapshot(reply.data);
      if (state.id !== record.stateId)
        throw new AsyncError("protocol", "Unexpected action-state identifier");
      if (options.onStateChange) options.onStateChange(state);
      if (state.finished) {
        if (!state.status)
          throw new AsyncError("action-failed", "Server action failed");
        return { value: result.value, response: result.response, state };
      }
      action = resource.actions.poll;
    }
  } catch (error) {
    const failure = timedOut
      ? new AsyncError("timeout", "Completion wait timed out", { cause: error })
      : asAsyncError(error);
    failure.response = result.response;
    if (!failure.envelope) failure.envelope = result.response.envelope;
    if (state) failure.state = state;
    throw failure;
  } finally {
    clearTimeout(timer);
    if (options.signal) options.signal.removeEventListener("abort", abort);
  }
}
