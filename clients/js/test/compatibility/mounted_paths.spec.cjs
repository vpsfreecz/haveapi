const assert = require("node:assert/strict");
const { test } = require("node:test");
const { harness, tick } = require("../helpers/async_bundle.cjs");

function action(path, namespace = "widget", parameters = {}, method = "POST") {
  return {
    path,
    method,
    aliases: [],
    blocking: false,
    input: { layout: "hash", namespace, parameters },
    output: { layout: "hash", namespace, parameters: {} },
  };
}
function description(mount, versionedAuth = false) {
  const string = { type: "String" };
  const tokenPath =
    mount + (versionedAuth ? "/v2" : "") + "/_auth/token/tokens";
  const token = (suffix) =>
    action(tokenPath + suffix, "token", {
      user: string,
      password: string,
      lifetime: string,
      token: string,
      code: string,
    });
  const state = mount + "/v2/action_states/{id}";
  return {
    meta: { namespace: "_meta" },
    authentication: {
      token: {
        http_header: "X-Token",
        resources: {
          token: {
            resources: {},
            actions: {
              request: token(""),
              verify: token("/verify"),
              renew: token("/renew"),
              revoke: token("/revoke"),
            },
          },
        },
      },
    },
    resources: {
      parents: {
        actions: {},
        resources: {
          widgets: {
            resources: {},
            actions: {
              run: {
                ...action(
                  mount + "/v2/parents/{parent_id}/widgets/{widget_id}",
                ),
                blocking: true,
              },
            },
          },
        },
      },
      action_state: {
        resources: {},
        actions: {
          show: action(state, "action_state", {}, "GET"),
          poll: action(
            state + "/poll",
            "action_state",
            {
              timeout: { type: "Float" },
              update_in: { type: "Float" },
              current: { type: "Integer" },
              total: { type: "Integer" },
              status: { type: "Boolean" },
            },
            "GET",
          ),
        },
      },
    },
  };
}
const described = (value) => ({
  status: true,
  version: "2.0",
  response: value,
});
const reply = (value, namespace = "widget", meta = {}) => ({
  status: true,
  response: { [namespace]: value, _meta: meta },
});
const state = (finished) =>
  reply(
    {
      id: 9,
      finished,
      status: true,
      current: finished ? 1 : 0,
      total: 1,
      can_cancel: true,
    },
    "action_state",
  );

for (const mount of ["", "/mount"]) {
  for (const trailing of ["", "/"]) {
    test(`callback and async described nested actions bind origin-root paths once at ${mount || "/"}${trailing}`, async () => {
      const { HaveAPI, requests } = harness();
      const base = "https://api.example" + mount + trailing;
      const model = description(mount);
      const callback = new HaveAPI.CallbackClient(base, { version: "2" });
      callback.useDescription(model);
      const resource = HaveAPI.CallbackClient.findResource(callback, [
        "parents",
        "widgets",
      ]);
      HaveAPI.CallbackClient.findAction(resource, "run").directInvoke(
        "id/space %",
        0,
        { params: {} },
      );
      const asyncClient = new HaveAPI.AsyncClient(base, { version: "2" });
      asyncClient.useDescription(model);
      const running = asyncClient
        .resource("parents")
        .resource("widgets")
        .action("run")("id/space %", 0, { params: {} });
      const expected =
        "https://api.example" +
        mount +
        "/v2/parents/id%2Fspace%20%25/widgets/0";
      assert.equal(requests[0].url, expected);
      assert.equal(requests[1].url, expected);
      requests[0].respond(reply({}));
      requests[1].respond(reply({}));
      await running;
      assert.equal(requests.length, 2);
    });
  }
}

test("mounted discovery, versions and public raw requests remain API-base-relative", async () => {
  for (const version of [undefined, "2"]) {
    const { HaveAPI, requests } = harness();
    const model = description("/mount");
    const callback = new HaveAPI.CallbackClient("https://api.example/mount/", {
      version,
    });
    let ready = false;
    callback.setup((_, ok) => {
      ready = ok;
    });
    const discovery =
      "https://api.example/mount/" + (version ? "v2/" : "?describe=default");
    assert.equal(requests[0].url, discovery);
    requests[0].respond(described(model));
    assert.equal(ready, true);
    callback.availableVersions(() => {});
    assert.equal(
      requests[1].url,
      "https://api.example/mount/?describe=versions",
    );
    requests[1].respond(described({ versions: ["2"], default: "2" }));
    const api = new HaveAPI.AsyncClient("https://api.example/mount/", {
      version,
    });
    const setup = api.setup();
    await tick();
    assert.equal(requests[2].url, discovery);
    requests[2].respond(described(model));
    await setup;
    const versions = api.availableVersions();
    assert.equal(
      requests[3].url,
      "https://api.example/mount/?describe=versions",
    );
    requests[3].respond(described({ versions: ["2"], default: "2" }));
    await versions;
    const raw = api.request({
      method: "GET",
      path: "/v2/widgets?existing=1",
      params: { count: 0 },
    });
    assert.equal(
      requests[4].url,
      "https://api.example/mount/v2/widgets?existing=1&count=0",
    );
    requests[4].respond(reply({}));
    await raw;
    const literal = api.request({ method: "GET", path: "/mount/v2/widgets" });
    assert.equal(requests[5].url, "https://api.example/mount/mount/v2/widgets");
    requests[5].respond(reply({}));
    await literal;
  }
});

for (const versionedAuth of [false, true]) {
  test(`callback and async token challenges preserve ${versionedAuth ? "versioned" : "global"} advertised routes`, async () => {
    const { HaveAPI, requests } = harness();
    const model = description("/mount", versionedAuth);
    const tokenBase =
      "https://api.example/mount" +
      (versionedAuth ? "/v2" : "") +
      "/_auth/token/tokens";
    const callback = new HaveAPI.CallbackClient("https://api.example/mount/", {
      version: "2",
    });
    let ready = false;
    callback.authenticate(
      "token",
      {
        user: "fixture-user",
        password: "fixture-password",
        callback: () => ({ code: "123456" }),
      },
      (_, ok) => {
        ready = ok;
      },
    );
    assert.equal(requests[0].url, "https://api.example/mount/v2/");
    requests[0].respond(described(model));
    assert.equal(requests[1].url, tokenBase);
    requests[1].respond(
      reply(
        { complete: false, token: "temporary", next_action: "verify" },
        "token",
      ),
    );
    assert.equal(requests[2].url, tokenBase + "/verify");
    assert.equal(JSON.parse(requests[2].body).token.token, "temporary");
    requests[2].respond(reply({ complete: true, token: "final" }, "token"));
    assert.equal(requests[3].url, "https://api.example/mount/v2/");
    assert.equal(requests[3].headers["X-Token"], "final");
    requests[3].respond(described(model));
    assert.equal(ready, true);
    callback.authProvider.renewToken();
    assert.equal(requests[4].url, tokenBase + "/renew");
    requests[4].respond(reply({ valid_to: "2030-01-01" }, "token"));
    callback.authProvider.resource.revoke({});
    assert.equal(requests[5].url, tokenBase + "/revoke");
    requests[5].respond(reply({}, "token"));
    const api = new HaveAPI.AsyncClient("https://api.example/mount/", {
      version: "2",
    });
    const authenticating = api.authenticate("token", {
      user: "fixture-user",
      password: "fixture-password",
      onChallenge: () => ({ code: "123456" }),
    });
    await tick();
    assert.equal(requests[6].url, "https://api.example/mount/v2/");
    requests[6].respond(described(model));
    await tick();
    assert.equal(requests[7].url, tokenBase);
    requests[7].respond(
      reply(
        { complete: false, token: "temporary", next_action: "verify" },
        "token",
      ),
    );
    await tick();
    assert.equal(requests[8].url, tokenBase + "/verify");
    requests[8].respond(reply({ complete: true, token: "final" }, "token"));
    await tick();
    assert.equal(requests[9].url, "https://api.example/mount/v2/");
    assert.equal(requests[9].headers["X-Token"], "final");
    requests[9].respond(described(model));
    await authenticating;
    assert.equal(requests.length, 10);
  });
}

test("callback and async state show/poll calls retain mounted advertised paths", async () => {
  const { HaveAPI, requests } = harness();
  const model = description("/mount");
  const callback = new HaveAPI.CallbackClient("https://api.example/mount/");
  callback.useDescription(model);
  let done = false;
  HaveAPI.CallbackClient.Action.waitForCompletion({
    client: callback,
    id: 9,
    reply: {},
    onDone: () => {
      done = true;
    },
  });
  assert.equal(requests[0].url, "https://api.example/mount/v2/action_states/9");
  requests[0].respond(state(false));
  assert.equal(
    new URL(requests[1].url).pathname,
    "/mount/v2/action_states/9/poll",
  );
  requests[1].respond(state(true));
  assert.equal(done, true);
  const api = new HaveAPI.AsyncClient("https://api.example/mount/");
  api.useDescription(model);
  const started = api.resource("parents").resource("widgets").action("run")(
    7,
    8,
  );
  requests[2].respond(reply({}, "widget", { action_state_id: 9 }));
  const waiting = api.waitForCompletion(await started, { timeoutMs: 1000 });
  assert.equal(requests[3].url, "https://api.example/mount/v2/action_states/9");
  requests[3].respond(state(false));
  await tick();
  assert.equal(
    new URL(requests[4].url).pathname,
    "/mount/v2/action_states/9/poll",
  );
  requests[4].respond(state(true));
  assert.equal((await waiting).state.finished, true);
  assert.equal(requests.length, 5);
});

test("descriptor paths reject authority, userinfo and control forms before transport or callback credential reads", () => {
  const { HaveAPI, requests } = harness();
  for (const unsafe of [
    "//evil.example/path",
    "https://evil.example/path",
    "@evil.example/path",
    "/path/@user",
    "/path\\escape",
    "/path\ncontrol",
  ]) {
    const model = description("/mount");
    model.resources.parents.resources.widgets.actions.run.path = unsafe;
    const callback = new HaveAPI.CallbackClient("https://api.example/mount/");
    callback.useDescription(model);
    let reads = 0;
    callback.authProvider = {
      credentials() {
        reads++;
      },
      headers() {
        reads++;
      },
      queryParameters() {
        reads++;
      },
    };
    const resource = HaveAPI.CallbackClient.findResource(callback, [
      "parents",
      "widgets",
    ]);
    assert.throws(
      () =>
        HaveAPI.CallbackClient.findAction(resource, "run").directInvoke({
          params: {},
        }),
      (error) => error.name === "ProtocolError",
    );
    assert.equal(reads, 0);
    const asyncClient = new HaveAPI.AsyncClient("https://api.example/mount/");
    assert.throws(
      () => asyncClient.useDescription(model),
      (error) => error.kind === "protocol",
    );
    const authModel = description("/mount");
    authModel.authentication.token.resources.token.actions.request.path =
      unsafe;
    assert.throws(
      () => asyncClient.useDescription(authModel),
      (error) => error.kind === "protocol",
    );
  }
  const invalidBase = new HaveAPI.CallbackClient(
    "https://user:password@api.example/mount/",
  );
  assert.throws(
    () => invalidBase.sameOriginUrl("/mount/v2/items", { actionPath: true }),
    (error) => error.name === "ProtocolError",
  );
  assert.equal(requests.length, 0);
});

test("OAuth relative URLs and exact trusted origins keep their existing semantics", () => {
  const { HaveAPI } = harness();
  const api = new HaveAPI.CallbackClient("https://api.example/mount/", {
    oauth2TrustedOrigins: ["https://auth.example"],
  });
  assert.equal(api.oauth2Url("/revoke"), "https://api.example/mount/revoke");
  assert.equal(api.oauth2Url("revoke"), "https://api.example/mount/revoke");
  assert.equal(
    api.oauth2Url("https://auth.example/revoke"),
    "https://auth.example/revoke",
  );
  assert.throws(
    () => api.oauth2Url("https://auth.example.evil/revoke"),
    (error) => error.name === "ProtocolError",
  );
  assert.throws(
    () =>
      api.sameOriginUrl("https://auth.example/revoke", {
        actionPath: true,
        trustedOrigins: ["https://auth.example"],
      }),
    (error) => error.name === "ProtocolError",
  );
});
