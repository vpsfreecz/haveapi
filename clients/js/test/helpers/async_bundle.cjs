const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

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
    respond(value, status = 200) {
      this.readyState = 4;
      this.status = status;
      this.responseText =
        typeof value === "string" ? value : JSON.stringify(value);
      if (this.onreadystatechange) this.onreadystatechange();
    }
    abort() {
      if (this.onabort) this.onabort();
    }
  }
  const context = {
    module: { exports: {} },
    exports: {},
    URL,
    Promise,
    AbortController,
    Date,
    setTimeout,
    clearTimeout,
    console: { log() {} },
    require: () => ({ XMLHttpRequest: XHR }),
  };
  vm.runInNewContext(
    fs.readFileSync(
      path.resolve(__dirname, "../../dist/haveapi-client.js"),
      "utf8",
    ),
    context,
  );
  return { HaveAPI: context.module.exports, requests };
}

function action(parameters = null, overrides = {}) {
  return {
    method: "POST",
    path: "/v1/validate",
    aliases: [],
    blocking: false,
    input: parameters && { layout: "hash", namespace: "widget", parameters },
    output: { layout: "hash", namespace: "widget", parameters: {} },
    ...overrides,
  };
}
function description(parameters = null) {
  return {
    authentication: {},
    meta: { namespace: "_meta" },
    resources: {
      widgets: { resources: {}, actions: { validate: action(parameters) } },
    },
  };
}
const reply = (data = {}, namespace = "widget") => ({
  status: true,
  response: { [namespace]: data, _meta: {} },
});
const tick = () => new Promise((resolve) => setImmediate(resolve));

module.exports = { harness, action, description, reply, tick };
