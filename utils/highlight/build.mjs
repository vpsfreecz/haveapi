import { build } from 'esbuild';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('.', import.meta.url));
const target = new URL('../../servers/ruby/lib/haveapi/public/js/', import.meta.url);
const languages = ['bash', 'http', 'xml', 'php', 'json', 'javascript', 'ruby', 'go', 'rust', 'python', 'typescript'];
const source = [
  "const hljs = require('highlight.js/lib/core');",
  ...languages.map(name => `hljs.registerLanguage('${name}', require('highlight.js/lib/languages/${name}'));`),
  'module.exports = hljs;'
].join('\n');
const result = await build({
  stdin: { contents: source, resolveDir: directory },
  bundle: true,
  minify: true,
  write: false,
  format: 'iife',
  globalName: 'hljs',
  target: 'es2017',
  supported: { 'template-literal': false },
  banner: { js: '/*! highlight.js 11.12.0 | BSD-3-Clause | See highlight-LICENSE */' }
});
const files = new Map([
  ['highlight.pack.js', result.outputFiles[0].text],
  ['highlight-LICENSE', await readFile(new URL('node_modules/highlight.js/LICENSE', import.meta.url), 'utf8')]
]);
for (const [name, content] of files) {
  const path = new URL(name, target);
  if (process.argv.includes('--check')) {
    if (await readFile(path, 'utf8') !== content) throw new Error(`${name} is stale; run npm run build`);
  } else {
    await writeFile(path, content);
  }
}
