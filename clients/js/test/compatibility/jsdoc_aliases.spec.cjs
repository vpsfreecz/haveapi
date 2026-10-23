const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {test} = require('node:test');
const aliases = require('../../jsdoc_aliases.js');
const root = path.resolve(__dirname, '../..');

test('fixed JSDoc alias fails closed for missing, duplicate or conflicting destinations', () => {
  assert.throws(() => aliases.transform('<h4 id="other">'), /exactly one/);
  assert.throws(() => aliases.transform('<h4 id="invoke"><h4 id="invoke">'), /exactly one/);
  assert.throws(() => aliases.transform('<h4 id="invoke"><div id="invoke">'), /exactly one/);
  assert.throws(() => aliases.transform('<div id="invoke__anchor"></div><h4 id="invoke">'), /collides/);
  assert.throws(() => aliases.transform('<span id="invoke__anchor"></span><span id="invoke__anchor"></span><h4 id="invoke">'), /collides/);
  const canonical = '<h4 class="name" id="invoke">invoke</h4>';
  const result = aliases.transform(canonical);
  assert.equal(aliases.transform(result), result);
  assert.equal((result.match(/id="invoke__anchor"/g) || []).length, 1);
  assert.ok(result.endsWith(canonical));
});

test('maintained JSDoc renders real API navigation and preserves the documented Action anchor', t => {
  const destination = fs.mkdtempSync(path.join(os.tmpdir(), 'haveapi-jsdoc-'));
  t.after(() => fs.rmSync(destination, {recursive: true, force: true}));
  const generated = spawnSync(process.execPath,
    [require.resolve('jsdoc/jsdoc.js'), '-c', 'jsdoc.json', '-d', destination],
    {cwd: root, encoding: 'utf8'});
  assert.equal(generated.status, 0, generated.stdout + generated.stderr);
  assert.equal(generated.stderr, '', 'JSDoc diagnostics must remain visible');
  aliases.write(destination);
  const pages = {
    'HaveAPI.Client.html': ['setup', 'authenticate'],
    'HaveAPI.Client.Action.html': ['invoke', 'invoke__anchor'],
    'HaveAPI.Client.Resource.html': []
  };
  const index = fs.readFileSync(path.join(destination, 'index.html'), 'utf8');
  assert.match(index, /HaveAPI/);
  for (const [page, ids] of Object.entries(pages)) {
    const html = fs.readFileSync(path.join(destination, page), 'utf8');
    assert.match(index, new RegExp('href="' + page.replaceAll('.', '\\.') + '"'));
    assert.match(html, /<nav>/);
    assert.match(html, /<h1[^>]*>Class:/);
    for (const id of ids)
      assert.equal((html.match(new RegExp('\\bid="' + id + '"', 'g')) || []).length, 1, page + '#' + id);
  }
  const actionPath = path.join(destination, 'HaveAPI.Client.Action.html');
  const first = fs.readFileSync(actionPath, 'utf8');
  aliases.write(destination);
  assert.equal(fs.readFileSync(actionPath, 'utf8'), first);
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  assert.match(readme, /HaveAPI\.Client\.Action\.html#invoke__anchor/);
});
