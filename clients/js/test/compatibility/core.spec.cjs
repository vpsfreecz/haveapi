const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

function harness() {
  const requests = [];
  class XHR {
    constructor() {
      this.headers = {};
      requests.push(this);
    }
    open(method, url) {
      this.method = method;
      this.url = url;
    }
    setRequestHeader(name, value) {
      this.headers[name] = value;
    }
    send(body) {
      this.body = body;
    }
    respond(body, status = 200) {
      this.status = status;
      this.responseText =
        typeof body === "string" ? body : JSON.stringify(body);
      this.readyState = 4;
      this.onreadystatechange();
    }
  }
  const context = {
    module: { exports: {} },
    exports: {},
    URL,
    console: { log() {} },
    Promise: undefined,
    AbortController: undefined,
    require(name) {
      assert.equal(name, "xmlhttprequest");
      return { XMLHttpRequest: XHR };
    },
  };
  const bundle = fs.readFileSync(
    path.resolve(__dirname, "../../dist/haveapi-client.js"),
    "utf8",
  );
  vm.runInNewContext(bundle, context);
  return { HaveAPI: context.module.exports, requests, context };
}

function tokenDescription() {
  const string = { type: "String" };
  function action(name, parameters) {
    return {
      method: "POST",
      path: "/v1/token/" + name,
      aliases: [],
      blocking: false,
      input: { layout: "hash", namespace: "token", parameters },
      output: { layout: "hash", namespace: "token", parameters: {} },
    };
  }
  return {
    meta: { namespace: "_meta" },
    resources: {},
    authentication: {
      token: {
        http_header: "X-Test-Token",
        resources: {
          token: {
            resources: {},
            actions: {
              request: action("request", {
                user: string,
                password: string,
                lifetime: string,
              }),
              challenge: action("challenge", { code: string, token: string }),
              renew: action("renew", {}),
              revoke: action("revoke", {}),
            },
          },
        },
      },
    },
  };
}
function described(description, version = "2.0") {
  return { status: true, version, response: description };
}
function tokenReply(fields) {
  return { status: true, response: { token: fields, _meta: {} } };
}

test("token authentication before setup preserves MFA continuation and description refresh", () => {
  const { HaveAPI, requests } = harness();
  const client = new HaveAPI.Client("https://api.example");
  let done = 0;
  let continueChallenge;
  assert.equal(
    client.authenticate(
      "token",
      {
        user: "user",
        password: "pass",
        callback(action, params, cont) {
          assert.equal(action, "challenge");
          assert.equal(params.code.type, "String");
          continueChallenge = cont;
        },
      },
      (c, status) => {
        assert.equal(c, client);
        assert.equal(status, true);
        done++;
      },
    ),
    undefined,
  );
  requests[0].respond(described(tokenDescription()));
  assert.equal(requests[1].url, "https://api.example/v1/token/request");
  requests[1].respond(
    tokenReply({
      complete: false,
      token: "challenge-token",
      next_action: "challenge",
    }),
  );
  assert.equal(done, 0);
  continueChallenge({ code: "123456" });
  assert.deepEqual(JSON.parse(requests[2].body).token, {
    code: "123456",
    token: "challenge-token",
  });
  requests[2].respond(
    tokenReply({
      complete: true,
      token: "final-token",
      valid_to: "2030-01-01",
    }),
  );
  assert.equal(done, 0);
  assert.equal(requests[3].method, "OPTIONS");
  assert.equal(requests[3].headers["X-Test-Token"], "final-token");
  requests[3].respond(described(tokenDescription()));
  assert.equal(done, 1);
  assert.equal(client.authProvider.token, "final-token");
});

test("token authentication failure and missing MFA handler keep legacy outcomes", () => {
  const { HaveAPI, requests } = harness();
  const client = new HaveAPI.Client("https://api.example");
  client.useDescription(tokenDescription());
  let outcome;
  client.authenticate(
    "token",
    { user: "user", password: "bad" },
    (c, status) => {
      outcome = status;
    },
  );
  requests[0].respond({ status: false, message: "denied", errors: {} }, 401);
  assert.equal(outcome, false);
  client.authenticate("token", { user: "user", password: "pass" }, () =>
    assert.fail("no final callback"),
  );
  assert.throws(
    () =>
      requests[1].respond(
        tokenReply({
          complete: false,
          token: "temporary",
          next_action: "challenge",
        }),
      ),
    (error) =>
      error === "Multi-factor authentication support must be implemented",
  );
});

test("existing-token reset=false is synchronous after description and logout ignores provider failure", () => {
  const { HaveAPI, requests } = harness();
  const client = new HaveAPI.Client("https://api.example");
  client.useDescription(tokenDescription());
  let ready = false;
  client.authenticate(
    "token",
    { token: "existing" },
    (c, status) => {
      ready = status;
    },
    false,
  );
  assert.equal(ready, true);
  assert.equal(requests.length, 0);
  client.authProvider.logout = (callback) => callback(client, false);
  let loggedOut;
  assert.equal(
    client.logout((c, status) => {
      loggedOut = status;
    }),
    undefined,
  );
  assert.equal(loggedOut, true);
  assert.equal(client._private.description, null);
  assert.equal(client.resources.length, 0);
});

test("setup and authentication retain different deferred protocol failure behavior", () => {
  const { HaveAPI, requests, context } = harness();
  const setup = new HaveAPI.Client("https://api.example");
  let outcome;
  setup.setup((c, status) => {
    outcome = status;
  });
  requests[0].respond(described(tokenDescription(), "9.0"));
  assert.equal(outcome, false);
  const auth = new HaveAPI.Client("https://api.example");
  auth.authenticate("token", { token: "existing" }, () =>
    assert.fail("no callback"),
  );
  assert.throws(
    () => requests[1].respond(described(tokenDescription(), "9.0")),
    (error) => error.name === "ProtocolError",
  );
  assert.equal(context.Authentication, HaveAPI.Client.Authentication);
  assert.equal(context.v1[0], "9");
  assert.equal(context.v2[0], "2");
});

test("legacy HTTP invalid JSON delivers false/undefined without constructing a Promise", () => {
  const { HaveAPI, requests } = harness();
  let result;
  const transport = new HaveAPI.Client.Http();
  assert.equal(
    transport.request({
      method: "GET",
      url: "https://api.example/test",
      headers: {},
      callback(status, body) {
        result = [status, body];
      },
    }),
    undefined,
  );
  requests[0].respond("not json");
  assert.deepEqual(result, [false, undefined]);
});

test("callback Parameters keeps constructor arity and receiver-based ownership behavior", () => {
  const { HaveAPI } = harness();
  const client = new HaveAPI.Client("https://api.example");
  client.useDescription({
    meta: { namespace: "_meta" },
    authentication: {},
    resources: {
      widgets: {
        resources: {},
        actions: {
          check: {
            method: "POST",
            path: "/check",
            input: {
              layout: "hash",
              namespace: "widget",
              parameters: { count: { type: "Integer" } },
            },
            output: null,
          },
        },
      },
    },
  });
  const prepared = client.widgets.check.prepareInvoke([{ count: 1 }]);
  assert.equal(prepared.params.constructor.length, 2);
  assert.equal(
    Object.prototype.hasOwnProperty.call(prepared.params, "_dictionaryPolicy"),
    false,
  );
  assert.throws(
    () =>
      client.widgets.check({ count: 1, hasOwnProperty: "legacy" }, () => {}),
    (error) => error.name === "TypeError",
  );
});
