'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../../../lib/haveapi/public/js');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'highlight.pack.js'), 'utf8'), context);
for (const language of ['bash', 'http', 'xml', 'php', 'json', 'javascript', 'ruby', 'go', 'rust', 'python', 'typescript']) {
  assert(context.hljs.getLanguage(language), language);
  const result = context.hljs.highlight('const text = "<script>";', { language, ignoreIllegals: true });
  assert(!result.value.includes('<script>'), language);
}
assert.equal(context.hljs.versionString, '11.12.0');
const messages = [];
context.importScripts = name => assert.equal(name, 'highlight.pack.js');
context.postMessage = value => messages.push(value);
vm.runInContext(fs.readFileSync(path.join(root, 'highlighter.js'), 'utf8'), context);
context.onmessage({ data: { language: 'unknown', code: '<script>&"\'' } });
assert.equal(messages.pop(), '&lt;script&gt;&amp;&quot;&#39;');
context.onmessage({ data: { language: 'go', code: 'package main' } });
assert(messages.pop().includes('hljs-keyword'));
context.hljs.highlight = () => { throw new Error('fixture failure'); };
context.onmessage({ data: { language: 'rust', code: '<unsafe>' } });
assert.equal(messages.pop(), '&lt;unsafe&gt;');
console.log('All bundled languages and safe worker fallbacks passed');
