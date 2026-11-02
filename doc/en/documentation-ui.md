# Browsing API documentation

Open a version endpoint such as `/v7.0/` for the overview and client
initialization examples. The overview lists the available client libraries and
configured API clients. Choose **Authentication** for sign-in examples or
**Resources** for the full resource directory. Nested resources have their own pages, with
breadcrumbs linking to their parents. The sidebar identifies the current
resource by its full dotted path, such as `vps.snapshot`, above its action links.

The brand identifies the API, with its version on a separate line. The API root
lists available versions. HaveAPI internals opens the framework README; its
sidebar links to the protocol and client-development references.

Resource URLs use `?resource=vps` or `?resource=vps.snapshot`; the directory uses
`?page=resources` and authentication uses `?page=authentication`. These selectors
apply only to HTML documentation, leaving API actions and OPTIONS descriptions
unchanged. A version URL without the final slash redirects to its canonical
slash URL and retains the query. Mounted APIs retain
their prefix, for example `/api/v7.0/?resource=vps`. The unselected API root
continues to list versions; a selector there uses the default version.
Malformed or ambiguous selectors return 400. Resources absent from the current
user's description return 404. Navigation, examples and legacy anchor mappings
use the same filtered description. Ordinary documentation pages use
`private, no-store`; compact search data has a separate private-cache policy
described below.

Each resource page shows that resource's own actions and links to its children.
The sidebar lists its direct subresources. While scrolling, the current action
expands to show its Input parameters, Output parameters and Examples links.
Authentication methods provide links to their sections in the same way.
Without JavaScript, all of these section links remain visible. Reference
headings have permalink icons for linking to a particular section.
Action links retain their existing `root-...` fragments. Old overview links
with resource, action or example fragments open the corresponding resource page
when JavaScript is enabled. Ordinary resource links work without JavaScript;
the resource directory remains usable without JavaScript.

## Search and visibility

Search is available in the sidebar on every documentation page. Press `/` to
focus it; on small screens this opens the navigation. The shortcut leaves normal
typing in editable fields alone. Search finds resource names, action
names, aliases and paths, and input or output parameter names, labels and types.
Versioned pages search their selected API version. The versions index and
HaveAPI internals search the default version, identified in the search label.
Search does not include protocol text, examples, defaults or validator values.

Results open the resource, action or parameter row. Queries use the normal
resource-directory page, such as `?page=resources&q=hostname`, and work without
JavaScript. With JavaScript enabled, using the search field loads a compact
list of searchable metadata. Further typing searches that list locally.
Resources appear before actions, followed by parameters. Resource results show
the full path, including parent resources. The list shows at most
20 matches and asks the reader to refine queries with more results. Submitting
the form opens the results page.

The first search may take time to load. The browser can reuse its private cached
copy when navigating between freshly rendered pages with the same visible API
metadata. Search follows the documentation snapshot shown on the page; an open
page can retain that snapshot until reloaded. Opening a result checks access
again. The versions index, internal pages and pages restored from browser history
load a fresh snapshot when search is used. The search enhancement does not save
queries or results in preferences or JavaScript storage.

Anonymous documentation shows all declared resources, actions and parameters.
Signed-in documentation and search results show only those accessible to the
current account. Open **Documentation settings** beside the API name for theme
choices and the available OAuth sign-in or account controls. Signed-in readers
see their username and **Sign out**. Supported OAuth clients also offer
**Switch user**, which ends the documentation session
and starts a fresh sign-in. If that next sign-in is cancelled, the old session
remains signed out. The note below the controls states which view is shown.
Each API request still checks authorization
for its particular operation; a documentation entry does not grant permission
to execute it.

Parameter Details contain a Validation rules table with one row per advertised
rule. Allowed values appear in code beside their display labels. String choices
have no added quotation marks; other values retain their types.
Validation messages and extra options remain available; unknown rules retain
their supplied details. The Required column, defaults and API validation
behavior are unchanged. On narrow screens, parameter tables and long code blocks
scroll within their own regions.

Version-specific navigation puts Authentication before Resources and indents
authentication methods beneath it. Technical references are linked under
HaveAPI internals in the versions-index sidebar, and retain their direct URLs.

## Documentation language

Open **Documentation settings** and use **Language**, above **Theme**, to select
**English** or **Česky**. Before a choice is saved, the documentation follows the
browser's weighted `Accept-Language` preferences, including regional tags such
as `cs-CZ` and `en-GB`, and falls back to English. Detecting a language does not
save it. Changing the select saves the choice and reloads the current page,
preserving its path, query and fragment.

A valid `doc_lang=en` or `doc_lang=cs` query takes precedence over the saved
`haveapi.docs.locale` cookie, then browser preferences, then English. The cookie
is host-only, scoped to the API mount, uses SameSite=Lax, and is Secure on HTTPS.
If cookies are unavailable, the query still selects the language for that page,
but the choice cannot persist through the cookie. With JavaScript, only the
select is shown. Without JavaScript, use the submit button after choosing a
language; native form submission does not preserve the fragment.
Search uses the page's effective documentation language without saving a choice.

The API reference and HaveAPI internal articles share this setting. Articles
without a Czech translation show the English source with a notice. Article
links and existing section fragments retain their public URLs. Documentation
language does not change API action requests, OPTIONS responses, account
language or the API's request-locale configuration.

## Themes and examples

The sidebar controls theme, programming language, client variant and example detail for
all examples on the page. Open **Documentation settings** and use the **Theme**
controls to select **Automatic**, **Light** or **Dark**. Automatic follows the
operating system. The versions index and shared internal pages use the same
layout and theme choices.

**Simple** examples focus on the operation and assume an initialized `api`
client, authenticated when required. **With error handling** demonstrates
additional error checks or diagnostics. Initialization and authentication
examples remain on their respective pages.

Choose a programming language first (labeled **Jazyk** in Czech). The Client selector appears when that language has
multiple variants, such as Callback and Async. The Examples selector appears
when the selected client supports more than one detail level on the current
page. If only one level is available, examples use it automatically.

A client can offer only Simple on an initialization page and both levels on an
action page. Each example uses With error handling only when that group supports
it; other groups remain Simple. A singleton choice preserves the saved detail
preference for pages and clients that support both levels. Replace the literal
credentials in authentication examples with the values for your application.

Use the copy icon inside a code block's top-right corner to copy its displayed code.
If the browser cannot copy it, select the code and copy it manually. Copying an
example does not change the selected language, detail or scroll position.

Without JavaScript, choose a programming language and press **Apply**. The page
reloads with that language's client variants. Choose the variant and example
detail, then press **Apply** again. The selected example opens in each group;
other examples stay available in their disclosure panels. These GET submissions
retain the current page, search query and explicit documentation language, and
may drop the fragment. They do not save example preferences. With JavaScript,
changes apply immediately and the Apply button is hidden. Explicit example
choices in a URL take precedence over saved choices for that page without
saving them on load.

The browser stores theme, programming language, client variant and example detail
in `haveapi.docs.preferences.v1`; its `language` field selects the programming
language. The documentation language uses its separate cookie. Preference
data contains no credentials or API responses. Choices are checked against the
clients available in the current API; an unavailable saved client uses an
available fallback.
Storage failures leave the controls usable for the current page. Without
JavaScript, native disclosure panels keep the examples readable.

## Extending documentation

Client renderers declare `language`, `language_label` and optional `variant`
metadata alongside their stable client `id`. Unspecified presentation metadata
falls back to the renderer's ID and label. Only available renderers appear;
Go, Rust and TypeScript API clients require their configured profiles. See
[client examples](client-examples.md) for renderer and profile configuration.

Set the server's optional `documentation_name` before mounting to use a specific
API name or canonical domain in the brand and page titles. Without it, the
reference displays the request host and any nondefault port. The name is display
text; it does not change action URLs, OAuth endpoints or redirects.

Renderers can declare `detail_levels :simple` or
`detail_levels :simple, :thorough`. Declarations are inherited; undeclared custom
renderers keep both levels for compatibility. Declare a single level when the
renderer has no separate error-handling format. A renderer can refine its choices
for each group with `detail_levels_for(kind, context:, result:,
auth_method: nil, auth_description: nil)`, using the already-rendered Simple
result. The base query preserves the inherited declaration, including for
custom limitation results. Return only a frozen `[:simple]` or
`[:simple, :thorough]`. This controls presentation and does not change direct
renderer calls or Context detail values. See the
[renderer extension contract](client-examples.md#renderer-extensions) for the
built-in policies and adapter interface.

HTML selection traverses description keys rather than Ruby constants or file
paths. Keep UI navigation separate from any complete private schema used by a
client generator for name resolution. New content should retain stable action
and example IDs, escaped source and the shared current-user description.

Search metadata comes from that request's authorized description. Versioned
HTML derives one compact projection and a content key; it includes only the key
and index URL in the page. The index contains names, labels, types, paths and
parent references, with no examples, defaults, validator values or account
identity. Ruby result pages and browser suggestions match the same projection.

The keyed index representation uses `private, max-age=86400, immutable` and
varies by credentials and the configured locale header. A network request still
authenticates, describes the current view and checks the key before returning
data or a conditional success. Changed views return 409 without index data.
Bootstrap responses, errors and responses changing cookies remain no-store.
There is no server snapshot cache, background permission polling or persistent
JavaScript index. Logout does not erase private HTTP-cache files; a fresh page
can reuse an entry only when its authorized metadata has the same content key.

## Browser sign-in

APIs can optionally configure an OAuth documentation client for browser sign-in.
The server keeps its client secret and uses a secure encrypted cookie for the
documentation session. This session applies only to HTML documentation; API
actions still use their ordinary credentials. See the
[OAuth setup guide](documentation-oauth.md) for configuration and HTTPS
requirements. APIs without that configuration show anonymous documentation and
no sign-in control. HTTP Basic, bearer headers and query credentials do not sign
readers into the documentation. Their API authentication examples remain available.

For a single-version API, the versions index uses that version's
documentation authentication and shows its actual account controls. With
multiple versions, the index hides account controls rather than assuming their
authentication is compatible. Internal articles remain neutral and may link to
the single version's authentication page without claiming a signed-in identity.

Documentation identity comes only from its valid OAuth session cookie. Cached
Basic credentials for another user do not change that identity or its controls;
an absent or invalid cookie leaves the reader anonymous. Ordinary API actions
and OPTIONS descriptions continue to use their existing authentication. See the
OAuth setup guide for enabling account selection on a dedicated documentation
client.
