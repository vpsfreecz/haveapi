# Documentation highlighter

The server ships a local highlight.js browser bundle, and loads no code from a CDN.
The npm packages are pinned in `package.json` and `package-lock.json`:
highlight.js 11.12.0 and esbuild 0.28.2. The bundle contains Bash, HTTP, XML, PHP,
JSON, JavaScript, Ruby, Go, Rust, Python and TypeScript. The adjacent
`highlight-LICENSE` retains highlight.js's BSD-3-Clause license.

From the top-level Nix shell, regenerate and verify the assets with:

```sh
cd utils/highlight
npm ci --ignore-scripts --no-audit --no-fund
npm run build
npm run check
```

Commit the lockfile, generated bundle and license together. The build disables
template literals so source grammar whitespace is represented by escapes in
the minified output. This preserves the grammar while avoiding trailing
whitespace in generated files.

The worker uses highlight.js's `highlight(source, {language})` API. Unknown
languages and highlighting errors return escaped plain text. The main thread
keeps the server's escaped source intact when workers are unavailable or fail.
Quick language/worker and keyboard-tab checks run through
`make test-documentation-assets`.
