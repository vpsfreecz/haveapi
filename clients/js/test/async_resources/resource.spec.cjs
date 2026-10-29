const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  createResource,
} = require("../tmp/async-resources/haveapi/async/resource.js");
const {
  AsyncResourceInstance,
} = require("../tmp/async-resources/haveapi/async/resource_instance.js");
const {
  AsyncResourceList,
} = require("../tmp/async-resources/haveapi/async/resource_list.js");

function action(path, overrides = {}) {
  return {
    method: "GET",
    path,
    aliases: [],
    blocking: false,
    input: {
      namespace: "widget",
      layout: "object",
      parameters: { label: { type: "String" } },
    },
    output: {
      namespace: "widget",
      layout: "object",
      parameters: { id: { type: "Integer" }, label: { type: "String" } },
    },
    ...overrides,
  };
}
function fixture() {
  const widget = {
    resources: {},
    actions: {
      show: action("/widgets/{id}", { aliases: ["find"] }),
      create: action("/widgets", { method: "POST" }),
      update: action("/widgets/{id}", { method: "PUT" }),
      list: action("/widgets", {
        output: { namespace: "widget", layout: "object_list", parameters: {} },
      }),
      hash: action("/hash", {
        output: { namespace: "widget", layout: "hash", parameters: {} },
      }),
      hash_list: action("/hash-list", {
        output: { namespace: "widget", layout: "hash_list", parameters: {} },
      }),
      empty: action("/empty", { output: null }),
      then: action("/then", { aliases: ["save", "__proto__"] }),
    },
  };
  widget.actions.show.output.parameters.owner = {
    type: "Resource",
    resource: ["owners"],
    value_id: "id",
    value_label: "label",
  };
  widget.resources.children = {
    resources: {},
    actions: { show: action("/widgets/{widget}/children/{child}") },
  };
  widget.resources.then = {
    resources: {},
    actions: { show: action("/child-then") },
  };
  const owners = {
    resources: {},
    actions: {
      show: action("/owners/{id}"),
      update: action("/owners/{id}", { method: "PUT" }),
    },
  };
  const requests = [];
  let currentGeneration = 1;
  let handler = () => result({ id: 7, label: "server" }, { path_params: [7] });
  const makeError = (kind, message, details = {}) =>
    Object.assign(new Error(message), { name: "AsyncError", kind, ...details });
  const context = {
    description: {
      resources: { widgets: widget, owners },
      authentication: {},
      meta: { namespace: "_meta" },
    },
    metaNamespace: "_meta",
    generation: 1,
    validateParams(desc, params) {
      return params || {};
    },
    makeError,
    recordInvocation(value, response, description) {
      return { value, response };
    },
    request(spec) {
      if (currentGeneration !== context.generation)
        return Promise.reject(
          makeError("protocol", "Stale resource generation"),
        );
      requests.push(spec);
      return Promise.resolve(handler(spec));
    },
  };
  return {
    context,
    requests,
    resource: createResource(context, ["widgets"]),
    widget,
    owners,
    respond(fn) {
      handler = fn;
    },
    invalidate() {
      currentGeneration++;
    },
    makeError,
  };
}
function result(data, meta = {}) {
  return {
    data,
    meta,
    envelope: { status: true, response: { widget: data, _meta: meta } },
    httpStatus: 200,
  };
}
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

test("aliases, nested currying and IDs are encoded once without shared path state", async () => {
  const f = fixture();
  const pending = [];
  f.respond((spec) => {
    const next = deferred();
    pending.push(next);
    return next.promise;
  });
  const first = f.resource("a/b").children.show("x%y");
  const second = f.resource("other").children.action("show").invoke("two");
  assert.equal(f.requests[0].path, "/widgets/a%2Fb/children/x%25y");
  assert.equal(f.requests[1].path, "/widgets/other/children/two");
  pending[1].resolve(result({ id: 2 }, { path_params: ["other", "two"] }));
  pending[0].resolve(result({ id: 1 }, { path_params: ["a/b", "x%y"] }));
  const a = await first;
  const b = await second;
  assert.notEqual(a.value, b.value);
  assert.equal(a.value.get("id"), 1);
  assert.equal(b.value.get("id"), 2);
  f.respond(() => result({ id: 7 }, { path_params: [7] }));
  await f.resource.find(7);
  assert.equal(f.requests[2].path, "/widgets/7");
});

test("caller options are snapshotted at dispatch and callbacks/validation reject via Promise", async () => {
  const f = fixture();
  const next = deferred();
  f.respond(() => next.promise);
  const params = { label: "submitted", nested: { x: 1 } };
  const meta = { includes: ["owner"] };
  const headers = { "X-Test": "before" };
  const promise = f.resource.show(7, { params, meta, headers });
  params.label = "later";
  params.nested.x = 2;
  meta.includes.push("other");
  headers["X-Test"] = "later";
  assert.equal(f.requests[0].params.label, "submitted");
  assert.equal(f.requests[0].params.nested.x, 1);
  assert.deepEqual(f.requests[0].meta.includes, ["owner"]);
  assert.equal(f.requests[0].headers["X-Test"], "before");
  next.resolve(result({ id: 7 }, { path_params: [7] }));
  await promise;
  await assert.rejects(
    f.resource.show(7, () => {}),
    { kind: "protocol" },
  );
  await assert.rejects(f.resource.show(7, { onReply() {} }), {
    kind: "protocol",
  });
  await assert.rejects(f.resource.show(7, { params: null }), {
    kind: "protocol",
  });
  f.context.validateParams = () => {
    throw f.makeError("validation", "bad input");
  };
  let rejected;
  assert.doesNotThrow(() => {
    rejected = f.resource.show(7);
  });
  await assert.rejects(rejected, { kind: "validation" });
  assert.equal(f.requests.length, 1);
});

test("resources/actions/instances/lists remain nonthenable and collisions use explicit lookup", async () => {
  const f = fixture();
  assert.equal(await f.resource, f.resource);
  assert.equal(f.resource.then, undefined);
  assert.equal(f.resource.action("then").then, undefined);
  const thenAction = f.resource.action("then");
  assert.equal(await thenAction, thenAction); // only local selection
  assert.equal(f.requests.length, 0);
  f.respond(() =>
    result(
      { id: 7, then: "attribute", save: "reserved", __proto__: "safe" },
      { path_params: [7] },
    ),
  );
  const loaded = await f.resource.action("then")();
  assert.equal(await loaded.value, loaded.value);
  assert.equal(loaded.value.then, undefined);
  assert.equal(loaded.value.get("then"), "attribute");
  assert.equal(typeof loaded.value.save, "function");
  assert.equal(loaded.value.get("save"), "reserved");
  assert.equal(typeof f.resource.resource("then").action("show"), "function");
  await loaded.value.action("__proto__")();
  f.respond(() =>
    result([{ id: 7, then: "item", _meta: { path_params: [7] } }], {
      total_count: 4,
    }),
  );
  const list = (await f.resource.list()).value;
  assert.equal(await list, list);
  assert.equal(list instanceof AsyncResourceList, true);
  assert.equal(list.items[0] instanceof AsyncResourceInstance, true);
  assert.equal(list.items[0].whenResolved, undefined);
  assert.equal(list.items[0].apiResponse, undefined);
  assert.equal(list.totalCount, 4);
  assert.equal(list.first(), list.last());
  assert.equal(list[0], list.first());
  assert.equal(list[99], undefined);
  assert.equal([...list][0], list.itemAt(0));
});

test("all output layouts keep fixed wrapper fields and independent per-item IDs", async () => {
  const f = fixture();
  f.respond(() =>
    result(
      [
        { id: 1, _meta: { path_params: [11] } },
        { id: 2, _meta: { path_params: [22] } },
      ],
      { total_count: 2 },
    ),
  );
  const listed = await f.resource.list();
  assert.deepEqual(Object.keys(listed), ["value", "response"]);
  assert.equal(listed.response.httpStatus, 200);
  assert.equal(listed.response.envelope.status, true);
  f.respond(() => result({ label: "item" }, {}));
  await listed.value.itemAt(0).action("show")();
  await listed.value.itemAt(1).action("show")();
  assert.equal(f.requests[1].path, "/widgets/11");
  assert.equal(f.requests[2].path, "/widgets/22");
  const data = { then: "raw", value: 1 };
  f.respond(() => result(data));
  assert.equal((await f.resource.hash()).value, data);
  const array = [data];
  f.respond(() => result(array));
  assert.equal((await f.resource.hash_list()).value, array);
  f.respond(() => result(null));
  assert.equal((await f.resource.empty()).value, null);
  f.respond(() => result([null]));
  await assert.rejects(
    f.resource.list(),
    (error) => error.kind === "protocol" && error.response.httpStatus === 200,
  );
});

test("new/field access/list iteration are local; create/update save publishes validated identity", async () => {
  const f = fixture();
  const value = f.resource.new({ label: "local" });
  assert.equal(value.isPersistent(), false);
  assert.equal(value.get("label"), "local");
  assert.equal(f.requests.length, 0);
  const next = deferred();
  f.respond(() => next.promise);
  const saving = value.save();
  assert.equal(f.requests[0].path, "/widgets");
  assert.equal(f.requests[0].params.label, "local");
  value.set("label", "later draft");
  assert.equal(f.requests[0].params.label, "local");
  assert.equal(value.isPersistent(), false);
  next.resolve(result({ id: 9, label: "created" }, { path_params: [9] }));
  const saved = await saving;
  assert.equal(saved.value, value);
  assert.equal(value.isPersistent(), true);
  assert.equal(value.get("id"), 9);
  f.respond(() => result({ id: 9, label: "updated" })); // metadata omitted: preserve the known binding
  await value.save();
  assert.equal(f.requests[1].path, "/widgets/9");
  assert.equal(value.get("label"), "updated");
  await value.action("show")();
  assert.equal(f.requests[2].path, "/widgets/9");
});

test("save failures retain local state; accepted unbound create cannot dispatch a duplicate", async () => {
  const f = fixture();
  const value = f.resource.new({ label: "local" });
  f.respond(() => result({ id: 99, label: "accepted" }));
  let accepted;
  await assert.rejects(value.save(), (error) => {
    accepted = error;
    return (
      error.kind === "protocol" &&
      error.reason === "accepted-unbound" &&
      error.response.envelope.status === true
    );
  });
  assert.equal(value.get("label"), "local");
  assert.equal(value.get("id"), undefined); // data.id is not binding metadata
  assert.equal(value.isPersistent(), false);
  await assert.rejects(value.save(), (error) => error === accepted);
  assert.equal(f.requests.length, 1);
  const loaded = new AsyncResourceInstance(
    f.context,
    ["widgets"],
    { id: 7, label: "prior" },
    [7],
    true,
  );
  f.respond(() =>
    result({ id: 8, label: "invalid replacement" }, { path_params: [] }),
  );
  await assert.rejects(loaded.save(), { kind: "protocol" });
  assert.equal(loaded.get("id"), 7);
  assert.equal(loaded.get("label"), "prior");
  f.respond(() => {
    throw f.makeError("api", "rejected");
  });
  await assert.rejects(loaded.save(), { kind: "api" });
  assert.equal(loaded.get("label"), "prior");
});

test("singleton create may succeed without identity; unbound public objects stay readable", async () => {
  const f = fixture();
  f.widget.actions.update.path = "/singleton";
  const singleton = f.resource.new({ label: "new" });
  f.respond(() => result({ label: "saved" }));
  await singleton.save();
  assert.equal(singleton.isPersistent(), true);
  const publicValue = (await f.resource.show(7)).value;
  assert.equal(publicValue.get("label"), "saved");
  await assert.rejects(publicValue.action("show")(), { kind: "protocol" });
});

test("explicit association loads use prefetched data or await HTTP without a half-shell", async () => {
  const f = fixture();
  const prefetched = new AsyncResourceInstance(
    f.context,
    ["widgets"],
    {
      id: 7,
      owner: {
        id: 3,
        label: "owner",
        _meta: { resolved: true, path_params: [3] },
      },
    },
    [7],
  );
  assert.equal(prefetched.get("owner").label, "owner");
  assert.equal(f.requests.length, 0);
  const cached = await prefetched.loadAssociation("owner");
  assert.equal(cached.response, null);
  assert.equal(cached.value instanceof AsyncResourceInstance, true);
  assert.equal((await prefetched.loadAssociation("owner")).value, cached.value);
  assert.equal(f.requests.length, 0);
  prefetched.set("owner", { id: 4, _meta: { path_params: [4] } });
  const next = deferred();
  f.respond(() => next.promise);
  const loading = prefetched.loadAssociation("owner");
  assert.equal(f.requests[0].path, "/owners/4");
  assert.equal(prefetched.get("owner").label, undefined);
  next.reject(f.makeError("transport", "offline"));
  await assert.rejects(loading, { kind: "transport" });
  f.respond(() => result({ id: 4, label: "loaded" }, { path_params: [4] }));
  const loaded = await prefetched.loadAssociation("owner");
  assert.equal(loaded.value.get("label"), "loaded");
  assert.equal(loaded.response.httpStatus, 200);
  assert.equal((await prefetched.loadAssociation("owner")).response, null);
  assert.equal(f.requests.length, 2);
});

test("abort signals reach transport; stale sends reject while dispatched results retain binding", async () => {
  const f = fixture();
  const controller = new AbortController();
  const next = deferred();
  f.respond((spec) => {
    assert.equal(spec.signal, controller.signal);
    return next.promise;
  });
  const pending = f.resource.show(7, { signal: controller.signal });
  f.invalidate();
  next.resolve(result({ id: 7 }, { path_params: [7] }));
  const old = (await pending).value;
  assert.equal(old.get("id"), 7);
  await assert.rejects(old.action("show")(), { kind: "protocol" });
  await assert.rejects(f.resource.show(8), { kind: "protocol" });
  assert.equal(f.requests.length, 1);
  const aborted = fixture();
  aborted.respond(
    (spec) =>
      new Promise((resolve, reject) => {
        const fail = () => reject(aborted.makeError("aborted", "stopped"));
        if (spec.signal.aborted) fail();
        else spec.signal.addEventListener("abort", fail, { once: true });
      }),
  );
  controller.abort();
  await assert.rejects(
    aborted.resource.show(7, { signal: controller.signal }),
    { kind: "aborted" },
  );
  const inFlight = new AbortController();
  const stopped = aborted.resource.show(7, { signal: inFlight.signal });
  inFlight.abort();
  await assert.rejects(stopped, { kind: "aborted" });
});

test("parameter snapshots preserve own keys without prototype inheritance", async () => {
  const f = fixture();
  f.context.validateParams = (description, params) => {
    assert.equal(Object.getPrototypeOf(params), null);
    assert.equal(Object.prototype.hasOwnProperty.call(params, "label"), true);
    return params;
  };
  await f.resource.show(7, { params: { label: "submitted" } });
  assert.equal(f.requests[0].params.label, "submitted");
});

test("local attribute entity leaves do not alter request metadata snapshots or normal cycle checks", async () => {
  const f = fixture();
  f.widget.actions.create.input.parameters.owner = {
    type: "Resource",
    value_id: "id",
  };
  const owner = new AsyncResourceInstance(
    f.context,
    ["owners"],
    { id: 3, label: "owner" },
    [3],
  );
  const nested = { note: "before" };
  const local = f.resource.new({ label: "draft", owner, nested });
  assert.equal(local.get("owner"), owner);
  assert.notEqual(local.get("nested"), nested);
  nested.note = "after";
  assert.equal(local.get("nested").note, "before");
  const pending = deferred();
  f.respond(() => pending.promise);
  const metadata = { owner, nested: { note: "before" } };
  const saving = local.save({ meta: metadata });
  assert.equal(f.requests[0].params.owner, 3);
  assert.notEqual(f.requests[0].meta.owner, owner);
  assert.equal(
    f.requests[0].meta.owner instanceof AsyncResourceInstance,
    false,
  );
  owner.set("id", 33);
  metadata.nested.note = "after";
  assert.equal(f.requests[0].params.owner, 3);
  assert.equal(f.requests[0].meta.nested.note, "before");
  pending.resolve(result({ id: 7, label: "saved" }, { path_params: [7] }));
  await saving;
  const cyclic = {};
  cyclic.self = cyclic;
  assert.throws(() => f.resource.new({ nested: cyclic }), { kind: "protocol" });
  const before = f.requests.length;
  await assert.rejects(f.resource.show(7, { meta: cyclic }), {
    kind: "protocol",
  });
  assert.equal(f.requests.length, before);
  Object.defineProperty(f.widget.actions.create.input.parameters, "__proto__", {
    value: { type: "Resource" },
    enumerable: true,
  });
  const invalid = f.resource.new({ label: "draft" });
  invalid.set("__proto__", {});
  await assert.rejects(
    invalid.save(),
    (error) =>
      error.kind === "validation" &&
      Object.getPrototypeOf(error.errors) === null &&
      Object.prototype.hasOwnProperty.call(error.errors, "__proto__"),
  );
  assert.equal(f.requests.length, before);
});
