const assert = require("node:assert/strict");
const { test } = require("node:test");
const { harness } = require("../helpers/async_bundle.cjs");

function fixture(valueId = "id") {
  const { HaveAPI, requests } = harness();
  const owner = { type: "Resource", resource: ["owners"], value_id: valueId };
  const action = (method, route, input) => ({
    method,
    path: route,
    aliases: [],
    blocking: false,
    input: input
      ? {
          namespace: "widget",
          layout: "object",
          parameters: { label: { type: "String" }, owner },
        }
      : null,
    output: {
      namespace: "widget",
      layout: "object",
      parameters: { id: { type: "Integer" }, label: { type: "String" }, owner },
    },
  });
  const api = new HaveAPI.AsyncClient("https://api.example");
  api.useDescription({
    meta: { namespace: "_meta" },
    authentication: {},
    resources: {
      widgets: {
        resources: {},
        actions: {
          show: action("GET", "/widgets/{id}"),
          create: action("POST", "/widgets", true),
          update: action("PUT", "/widgets/{id}", true),
        },
      },
      owners: {
        resources: {},
        actions: {
          show: {
            ...action("GET", "/owners/{id}"),
            output: {
              namespace: "owner",
              layout: "object",
              parameters: { id: { type: "Integer" }, key: { type: "Integer" } },
            },
          },
        },
      },
    },
  });
  const reply = (data, id = 7) => ({
    status: true,
    response: { widget: data, _meta: { path_params: [id] } },
  });
  async function entity(data = { [valueId]: 3 }) {
    const pending = api.resource("owners").action("show")(3);
    requests.at(-1).respond({
      status: true,
      response: { owner: data, _meta: { path_params: [3] } },
    });
    return (await pending).value;
  }
  return {
    HaveAPI,
    api,
    requests,
    reply,
    entity,
    widgets: api.resource("widgets"),
  };
}
const wireBody = (request) => JSON.parse(request.body);

for (const entry of ["direct", "new attributes", "set then save"]) {
  test(`Resource entity inputs normalize through actual Parameters: ${entry}`, async () => {
    const f = fixture();
    const owner = await f.entity();
    const attributes = { label: "draft", owner };
    let pending;
    if (entry === "direct")
      pending = f.widgets.action("create")({ params: attributes });
    else {
      const local = f.widgets.new(
        entry === "new attributes" ? attributes : { label: "draft" },
      );
      if (entry === "set then save") local.set("owner", owner);
      assert.equal(local.get("owner"), owner);
      pending = local.save();
    }
    // Install a handler before awaiting so a pre-dispatch validation rejection is observed.
    pending.catch(() => {});
    const observed = pending;
    assert.equal(
      f.requests.length,
      2,
      "save must dispatch exactly one create after owner load",
    );
    assert.deepEqual(wireBody(f.requests[1]), {
      widget: { label: "draft", owner: 3 },
    });
    f.requests[1].respond(
      f.reply({
        id: 7,
        label: "saved",
        owner: { id: 3, _meta: { path_params: [3] } },
      }),
      201,
    );
    await observed;
    assert.equal(owner.get("id"), 3);
    assert.equal(attributes.owner, owner);
  });
}

for (const resolved of [false, true]) {
  test(`server-returned association records normalize for update without resolving or changing binding: resolved=${resolved}`, async () => {
    const f = fixture();
    const loading = f.widgets.action("show")(7);
    f.requests[0].respond(
      f.reply({
        id: 999,
        label: "loaded",
        owner: { id: 3, _meta: { resolved, path_params: [3] } },
      }),
    );
    const local = (await loading).value;
    const original = local.get("owner");
    const pending = local.save();
    pending.catch(() => {});
    assert.equal(f.requests.length, 2);
    assert.equal(f.requests[1].url, "https://api.example/widgets/7");
    assert.deepEqual(wireBody(f.requests[1]), {
      widget: { label: "loaded", owner: 3 },
    });
    assert.equal(local.get("owner"), original);
    f.requests[1].respond(
      f.reply({ id: 999, label: "updated", owner: original }),
    );
    await pending;
  });
}

test("custom Resource value_id uses only the declared own identifier and retains validation errors", async () => {
  const f = fixture("key");
  const owner = await f.entity({ id: 99, key: 3 });
  const local = f.widgets.new({ label: "custom", owner });
  const saving = local.save();
  saving.catch(() => {});
  assert.equal(f.requests.length, 2);
  assert.equal(wireBody(f.requests[1]).widget.owner, 3);
  f.requests[1].respond(f.reply({ id: 7, label: "saved" }));
  await saving;
  for (const invalid of [
    { id: 99 },
    { key: undefined },
    Object.assign(Object.create({ key: 3 }), { id: 99 }),
    { key: "invalid" },
    { key: 1.5 },
    { key: null },
  ]) {
    const draft = f.widgets.new({ label: "invalid" });
    draft.set("owner", invalid);
    const count = f.requests.length;
    await assert.rejects(draft.save(), (error) => error.kind === "validation");
    assert.equal(f.requests.length, count);
    assert.equal(draft.get("owner"), invalid);
    assert.equal(draft.isPersistent(), false);
  }
  const unbound = await f.entity({ id: 99 });
  const missing = f.widgets.new({ owner: unbound });
  const count = f.requests.length;
  await assert.rejects(missing.save(), (error) => error.kind === "validation");
  assert.equal(f.requests.length, count);
  assert.equal(missing.get("owner"), unbound);
});

test("save snapshots selected entity and scalar values before callers mutate local fields", async () => {
  const f = fixture();
  const owner = await f.entity();
  const local = f.widgets.new({ label: "before", owner });
  const saving = local.save();
  saving.catch(() => {});
  assert.equal(f.requests.length, 2);
  owner.set("id", 44);
  local.set("label", "after");
  local.set("owner", 55);
  assert.deepEqual(wireBody(f.requests[1]), {
    widget: { label: "before", owner: 3 },
  });
  f.requests[1].respond(
    { status: false, message: "rejected", errors: { owner: ["denied"] } },
    422,
  );
  await assert.rejects(saving, (error) => error.kind === "api");
  assert.equal(local.get("label"), "after");
  assert.equal(local.get("owner"), 55);
  assert.equal(local.isPersistent(), false);
});

for (const body of [
  { status: true, response: { _meta: {} } },
  { status: true },
  { status: true, response: { _meta: [] } },
]) {
  test(`definitely accepted create cannot repeat after invalid representation: ${JSON.stringify(body)}`, async () => {
    const f = fixture();
    const local = f.widgets.new({ label: "retained" });
    const pending = local.save();
    let accepted;
    const checked = assert.rejects(pending, (error) => {
      accepted = error;
      return (
        error.kind === "protocol" &&
        error.reason === "accepted-unbound" &&
        error.response.httpStatus === 201 &&
        error.response.envelope.status === true
      );
    });
    f.requests[0].respond(body, 201);
    await checked;
    assert.equal(local.get("label"), "retained");
    assert.equal(local.get("id"), undefined);
    assert.equal(local.isPersistent(), false);
    await assert.rejects(local.save(), (error) => error === accepted);
    assert.equal(f.requests.length, 1);
  });
}

test("ambiguous create transport failure retains draft without claiming acceptance or suppressing a later save", async () => {
  const f = fixture();
  const local = f.widgets.new({ label: "retained" });
  const first = local.save();
  const checked = assert.rejects(
    first,
    (error) => error.kind === "transport" && error.reason === undefined,
  );
  f.requests[0].onerror();
  await checked;
  assert.equal(local.get("label"), "retained");
  assert.equal(local.isPersistent(), false);
  const next = local.save();
  assert.equal(f.requests.length, 2);
  f.requests[1].respond(f.reply({ id: 7, label: "saved" }), 201);
  await next;
});

for (const [body, status, kind] of [
  [{ status: false, message: "denied" }, 422, "api"],
  ["invalid json", 201, "protocol"],
  [{ status: "true", response: {} }, 201, "protocol"],
]) {
  test(`no accepted-create latch without validated success: ${JSON.stringify(body)}`, async () => {
    const f = fixture();
    const local = f.widgets.new({ label: "draft" });
    const first = local.save();
    const checked = assert.rejects(
      first,
      (error) => error.kind === kind && error.reason === undefined,
    );
    f.requests[0].respond(body, status);
    await checked;
    assert.equal(local.get("label"), "draft");
    assert.equal(local.isPersistent(), false);
    const next = local.save();
    assert.equal(f.requests.length, 2);
    f.requests[1].respond(f.reply({ id: 7, label: "saved" }), 201);
    await next;
  });
}
