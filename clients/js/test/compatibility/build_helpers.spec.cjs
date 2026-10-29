const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");
const acorn = require("acorn");

const root = path.resolve(__dirname, "../..");
const bundle = fs.readFileSync(
  path.join(root, "dist/haveapi-client.js"),
  "utf8",
);

test("distributed UMD payload parses as ES5 and bundles its licensed helpers", () => {
  acorn.parse(bundle, { ecmaVersion: 5 });
  assert.match(bundle, /Bundled tslib license/);
  assert.match(bundle, /Permission to use, copy, modify, and\/or distribute/);
  assert.doesNotMatch(bundle, /require\s*\(\s*['"]tslib(?:\/[^'"]*)?['"]\s*\)/);
  assert.doesNotMatch(bundle, /\bthis\s*&&\s*this\.__/);
  function declarations(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const filename = path.join(directory, entry.name);
      if (entry.isDirectory()) declarations(filename);
      else if (entry.name.endsWith(".d.ts"))
        assert.doesNotMatch(
          fs.readFileSync(filename, "utf8"),
          /['"]tslib(?:\/[^'"]*)?['"]/,
          filename,
        );
    }
  }
  declarations(path.join(root, "dist/types"));
});

test("prepared tooling excludes obsolete wrappers without adding runtime helpers", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json")));
  // Inspect the local lock produced by dependency preparation.
  const lock = JSON.parse(
    fs.readFileSync(path.join(root, "package-lock.json")),
  );
  assert.equal(manifest.dependencies.tslib, undefined);
  assert.equal(manifest.devDependencies.tslib, "2.8.1");
  assert.equal(manifest.main, "dist/haveapi-client.js");
  assert.equal(manifest.types, "dist/types/haveapi.d.ts");
  for (const [name, entry] of Object.entries(lock.packages)) {
    assert.doesNotMatch(
      name,
      /node_modules\/(?:gulp-jsdoc3|ink-docstrap|tmp)$/,
    );
    assert.ok(!(name.endsWith("/rimraf") && entry.version === "2.7.1"), name);
    assert.ok(!(name.endsWith("/inflight") && entry.version === "1.0.6"), name);
    assert.ok(!(name.endsWith("/glob") && entry.version === "7.2.3"), name);
  }
});

function load(mode, modern) {
  const requests = [];
  const imports = [];
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
    respond(value) {
      this.status = 200;
      this.readyState = 4;
      this.responseText = JSON.stringify(value);
      this.onreadystatechange();
    }
  }
  const context = {
    URL,
    setTimeout,
    clearTimeout,
    console: { log() {} },
    Promise: modern ? Promise : undefined,
    AbortController: modern ? AbortController : undefined,
    globalThis: undefined,
  };
  for (const name of ["__assign", "__awaiter", "__generator", "__extends"]) {
    context[name] = function () {
      throw new Error("polluted global helper used: " + name);
    };
  }
  let namespace;
  if (mode === "commonjs") {
    context.global = context;
    context.module = { exports: {} };
    context.exports = context.module.exports;
    context.require = (name) => {
      imports.push(name);
      assert.equal(name, "xmlhttprequest");
      return { XMLHttpRequest: XHR };
    };
  } else {
    context.window = { XMLHttpRequest: XHR };
    if (mode === "amd") {
      context.define = (dependencies, factory) => {
        assert.equal(
          dependencies.length,
          0,
          "no external tslib AMD dependency",
        );
        namespace = factory();
      };
      context.define.amd = {};
    }
  }
  vm.runInNewContext(bundle, context);
  namespace =
    mode === "commonjs"
      ? context.module.exports
      : mode === "amd"
        ? namespace
        : context.HaveAPI;
  return { namespace, requests, imports };
}

for (const mode of ["commonjs", "amd", "browser"]) {
  test(`${mode} callback loads independently of polluted helpers and modern globals`, () => {
    const { namespace, imports } = load(mode, false);
    assert.equal(namespace.Client, namespace.CallbackClient);
    assert.equal(typeof namespace.AsyncClient, "function");
    const client = new namespace.CallbackClient("https://api.example");
    client.useDescription({
      authentication: {},
      meta: { namespace: "_meta" },
      resources: {},
    });
    assert.deepEqual(Array.from(client.resources), []);
    assert.deepEqual(imports, mode === "commonjs" ? ["xmlhttprequest"] : []);
  });

  test(`${mode} async setup uses bundled assign/awaiter/generator/extends helpers`, async () => {
    const { namespace, requests } = load(mode, true);
    const client = new namespace.AsyncClient("https://api.example");
    const setup = client.setup();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(requests.length, 1);
    requests[0].respond({
      version: "2.0",
      status: true,
      response: {
        authentication: {},
        meta: { namespace: "_meta" },
        resources: {},
      },
    });
    await setup;
    assert.deepEqual(Array.from(client.resources), []);
    assert.throws(
      () => client.resource("missing"),
      (error) =>
        error instanceof namespace.AsyncError && error.kind === "protocol",
    );
  });
}
