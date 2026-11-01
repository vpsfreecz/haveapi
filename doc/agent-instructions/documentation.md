# Documentation articles

Public article sources live in `doc/en/` and `doc/cs/`. English is the fallback
for an article without a Czech translation. The shared internals landing page
is `readme.md`; the Ruby server README links to that source. Keep public article
IDs and URLs independent of source directories: `doc/en/protocol.md` and
`doc/cs/protocol.md` both serve `/doc/protocol`, including its existing `.md`
alias. Do not retain flat `doc/*.md` copies of moved articles.

Use relative source links that work in the repository. A sibling article uses
`typed-input-validation.md`; a guide available only in English uses
`../en/documentation-ui.md` from Czech sources. Shared assets remain outside the
locale directories, for example `../protocol.png`. The server maps these links
to the existing mounted documentation routes. Links to repository code need
one more parent component than the former flat source layout, for example
`../../clients/typescript/README.md`.

Keep English fragment IDs when translating headings. Czech sources use explicit
HTML headings such as `<h2 id="authentication">Autentizace</h2>` followed by a
blank line; update the translated table of contents through framework catalog
keys. Do not derive public fragment IDs from translated titles.

Translate prose and human-readable authored comments. Preserve commands,
identifiers, literals, URLs, headers, wire samples and noncomment program text.
Do not translate an already rendered program or change sample values. Shared
JSON-schema definitions stay in `doc/json-schema.erb`; both language versions
use identical machine data. Only surrounding presentation, including the
`haveapi.documentation.schema.envelope` heading, comes from the framework catalog.

Run `make doc` in the declared Nix environment before server specs or packaging.
`utils/copydoc.sh` copies both article trees to `servers/ruby/doc/{en,cs}/`,
generates both schema presentations from the shared template and catalog, and
copies shared assets. Generated server documents are ignored build output.
The server gem includes nested documentation; `check_doc` rejects missing or
empty required files. Packaging specs extract a real gem and request both
languages without using checkout article sources. See
[development commands](development.md) for the relevant checks and
[localization](localization.md) for catalog maintenance.
