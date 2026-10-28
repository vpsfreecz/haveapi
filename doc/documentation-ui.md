# Browsing API documentation

Open a version endpoint such as `/v7.0/` for the overview and client
initialization examples. The overview lists the available client libraries and
configured SDKs. Choose **Authentication** for sign-in examples or **Resources**
for the full resource directory. Nested resources have their own pages, with
breadcrumbs linking to their parents. The sidebar identifies the current
resource by its full display path above its action links.

The brand identifies the API, with its version on a separate line. The API root
lists available versions. HaveAPI internals contains the framework, protocol
and client-development references; its sidebar provides the reference links.

Resource URLs use `?resource=vps` or `?resource=vps.snapshot`; the directory uses
`?page=resources` and authentication uses `?page=authentication`. These selectors
apply only to HTML documentation, leaving API actions and OPTIONS descriptions
unchanged. Mounted APIs retain
their prefix, for example `/api/v7.0/?resource=vps`. The unselected API root
continues to list versions; a selector there uses the default version.
Malformed or ambiguous selectors return 400. Resources absent from the current
user's description return 404. Navigation, examples and legacy anchor mappings
use the same filtered description. Ordinary documentation pages use
`private, no-store`; compact search data has a separate private-cache policy
described below.

Each resource page shows that resource's own actions and links to its children.
Action links retain their existing `root-...` fragments. Old overview links
with resource, action or example fragments open the corresponding resource page
when JavaScript is enabled. Ordinary resource links work without JavaScript;
the resource directory remains usable without JavaScript.

## Search and visibility

Search is available on every documentation page. It finds resource names, action
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
current account. Account controls sit beside the theme control at the top of the
sidebar. Open **Account** to see the signed-in username and **Sign out**. The note below the controls states which view is shown.
Each API request still checks authorization
for its particular operation; a documentation entry does not grant permission
to execute it.

Parameter Details contain a Validation rules table with one row per advertised
rule. Allowed values appear as typed API literals beside their display labels.
Validation messages and extra options remain available; unknown rules retain
their supplied details. The Required column, defaults and API validation
behavior are unchanged. On narrow screens, parameter tables and long code blocks
scroll within their own regions.

Version-specific navigation puts Authentication before Resources and indents
authentication methods beneath it. Technical references are linked under
HaveAPI internals in the versions-index sidebar, and retain their direct URLs.

## Themes and examples

The sidebar controls theme, language, client variant and example detail for
all examples on the page. Open the theme control to select **Automatic**,
**Light** or **Dark**; Automatic follows the operating system. The versions index
and shared internal pages use the same layout and theme choices.

**Simple** examples focus on the operation and assume an initialized `api`
client, authenticated when required. **With error handling** includes additional
setup or error handling where it helps. Initialization and authentication
examples remain on their respective pages.

The detail selector appears only when the selected client supports both levels.
HTTP, curl and CLI examples use their single format. Selecting one of these
clients preserves the saved detail choice for clients that support it.

Use the copy icon in an example's corner to copy the currently displayed code.
If the browser cannot copy it, select the code and copy it manually. Copying an
example does not change the selected language, detail or scroll position.

The browser stores these choices in `haveapi.docs.preferences.v1`. Preference
data contains no credentials or API responses. Choices are checked against the
clients available in the current API; an unavailable saved client uses an
available fallback.
Storage failures leave the controls usable for the current page. Without
JavaScript, native disclosure panels keep the examples readable.

## Extending documentation

Client renderers declare `language`, `language_label` and optional `variant`
metadata alongside their stable client `id`. Unspecified presentation metadata
falls back to the renderer's ID and label. Only available renderers appear;
generated SDKs require their configured profiles. See
[client examples](client-examples.md) for renderer and profile configuration.

Set the server's optional `documentation_name` before mounting to use a specific
API name or canonical domain in the brand and page titles. Without it, the
reference displays the request host and any nondefault port. The name is display
text; it does not change action URLs, OAuth endpoints or redirects.

Renderers can declare `detail_levels :simple` or
`detail_levels :simple, :thorough`. Declarations are inherited; undeclared custom
renderers keep both levels for compatibility. Declare a single level when the
renderer has no separate error-handling format. This controls presentation and
does not change direct renderer calls or Context detail values.

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
