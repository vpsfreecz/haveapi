const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createRequire } = require("node:module");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");

const root = path.resolve(__dirname, "../..");

test("JSDoc resolves the selected Markdown and anchor packages through its scoped overrides", () => {
  const jsdocRequire = createRequire(require.resolve("jsdoc/package.json"));
  for (const [name, version] of [
    ["markdown-it", "15.0.3"],
    ["markdown-it-anchor", "10.0.0"],
  ]) {
    assert.equal(jsdocRequire(name + "/package.json").version, version);
    assert.equal(jsdocRequire.resolve(name), require.resolve(name));
  }
  assert.equal(require("linkify-it/package.json").version, "6.1.0");
});

test("the actual JSDoc Markdown renderer preserves independent headings, links and code", (t) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "haveapi-jsdoc-markdown-"),
  );
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const output = path.join(directory, "rendered.json");
  const plugin = path.join(directory, "probe.cjs");
  const fixture = path.join(directory, "fixture.js");
  const config = path.join(directory, "jsdoc.json");
  const source = [
    "# Repeated heading",
    "",
    "# Repeated heading",
    "",
    "[Manual](https://manual.example.test/path)",
    "",
    "{@link HaveAPI.Client.Action#invoke|invoke}",
    "",
    "https://bare.example.test/path",
    "",
    "```js",
    'const sample = "<tag>";',
    "```",
    "",
    "<em>retained HTML</em>",
  ].join("\n");
  fs.writeFileSync(
    fixture,
    "/**\n" +
      source
        .split("\n")
        .map((line) => " * " + line)
        .join("\n") +
      "\n * @class MarkdownProbe\n */\nfunction MarkdownProbe() {}\n",
  );
  // Run inside JSDoc's real loader/plugin environment; do not patch its modules.
  fs.writeFileSync(
    plugin,
    `
exports.handlers = {processingComplete() {
  const markdown = require('jsdoc/util/markdown');
  const parser = markdown.getParser();
  const source = ${JSON.stringify(source)};
  require('fs').writeFileSync(${JSON.stringify(output)}, JSON.stringify({
    first: parser(source), second: parser(source), fresh: markdown.getParser()(source)
  }));
}};
`,
  );
  fs.writeFileSync(
    config,
    JSON.stringify({
      source: { include: [path.join(root, "build"), fixture] },
      plugins: ["plugins/markdown", plugin],
      markdown: { idInHeadings: true },
      opts: { destination: path.join(directory, "html"), recurse: true },
    }),
  );
  const generated = spawnSync(
    process.execPath,
    [require.resolve("jsdoc/jsdoc.js"), "-c", config],
    { cwd: root, encoding: "utf8" },
  );
  assert.equal(generated.status, 0, generated.stdout + generated.stderr);
  assert.equal(generated.stderr, "", "JSDoc diagnostics must stay visible");
  const rendered = JSON.parse(fs.readFileSync(output, "utf8"));
  assert.equal(
    rendered.first,
    rendered.second,
    "heading IDs reset for a new document on the same parser",
  );
  assert.equal(
    rendered.first,
    rendered.fresh,
    "fresh parser retains the same heading contract",
  );
  assert.match(
    rendered.first,
    /<h1 id="repeated-heading">Repeated heading<\/h1>/,
  );
  assert.match(
    rendered.first,
    /<h1 id="repeated-heading-1">Repeated heading<\/h1>/,
  );
  assert.doesNotMatch(rendered.first, /tabindex=/);
  assert.match(
    rendered.first,
    /<a href="https:\/\/manual\.example\.test\/path">Manual<\/a>/,
  );
  assert.match(
    rendered.first,
    /\{@link HaveAPI\.Client\.Action#invoke\|invoke\}/,
  );
  assert.match(rendered.first, /<p>https:\/\/bare\.example\.test\/path<\/p>/);
  assert.doesNotMatch(rendered.first, /href="https:\/\/bare\.example/);
  assert.match(
    rendered.first,
    /<pre class="prettyprint source lang-js"><code>/,
  );
  assert.match(rendered.first, /&quot;&lt;tag>&quot;/);
  assert.match(rendered.first, /<em>retained HTML<\/em>/);
  const page = fs.readFileSync(
    path.join(directory, "html/MarkdownProbe.html"),
    "utf8",
  );
  assert.match(page, /<nav>/);
  assert.match(page, /href="HaveAPI\.Client\.Action\.html#invoke"/);
  assert.match(page, /id="repeated-heading"/);
  assert.match(page, /id="repeated-heading-1"/);
});
