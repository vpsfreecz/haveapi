# OAuth sign-in for HTML documentation

The Ruby server can use an existing OAuth provider to sign readers into its HTML
documentation. This is an optional confidential client: the server exchanges
authorization codes and keeps the client secret out of the browser. Passwords,
MFA, account recovery and optional SSO remain with the provider.

## Configure the client

Register a dedicated confidential client with your OAuth provider. Use the exact
HTTPS callback `<API mount>_documentation/oauth/callback`, fixed access-token
expiry and no refresh token. Keep existing default OAuth clients unchanged.

Configure the documentation client before mounting the server:

```ruby
api.documentation_oauth(
  client_id: ENV.fetch('DOCUMENTATION_CLIENT_ID'),
  client_secret: ENV.fetch('DOCUMENTATION_CLIENT_SECRET'),
  redirect_uri: 'https://docs.example.test/api/_documentation/oauth/callback',
  session_secret: File.binread('/run/secrets/documentation-session'),
  scope: ['all'],
  session_lifetime: 3600
)
api.mount('/api/')
```

Generate at least 64 bytes of cryptographically random session secret material
once, keep it private, and supply the same value to every worker. Do not generate
it on each startup. Changing it signs existing documentation sessions out. Client
credentials and session secrets must not be committed or included in diagnostics.

`scope` defaults to `[]`. Request only the scopes needed by the application.
vpsAdmin uses `['all']` to describe the actions available to the signed-in user's
role. Its resulting bearer token can also authorize API requests, so keeping the
documentation cookie out of API authentication is essential.

`session_lifetime` defaults to 3600 seconds and accepts integers from 1 to 86400.
The actual session ends at the earlier of this limit and the provider's access
token expiry. No refresh token is stored or used.

`switch_user` defaults to `false` and accepts only `true` or `false`. Enable it
only after verifying that a fresh authorization for this dedicated client lets
the reader enter different credentials. For vpsAdmin, this requires a dedicated
nondefault client with `allow_single_sign_on=false`. This option asserts that
the operator has checked that behavior; it does not discover account-selection
support or send `prompt` or `select_account` parameters.

The callback must be an absolute HTTPS URL with the exact mounted callback path,
without credentials, query or fragment. The server takes authorize, token and
revoke endpoints from its default version's configured OAuth provider metadata
at mount time. Those endpoints must also use HTTPS. It does not discover an
issuer from a browser request or follow endpoint redirects. Missing providers,
invalid configuration and repeated or late configuration fail startup.

## HTTPS and worker requirements

Serve the documentation at the configured HTTPS origin. The Rack request scheme
and host must reflect that origin. When using a reverse proxy, configure trusted
forwarding in the server/proxy; do not trust arbitrary client-supplied forwarding
headers. A private development CA must be trusted by both the reader's browser
and the server's standard HTTPS trust store. Never disable peer verification.

Token and revoke exchanges use bounded HTTPS requests. If the provider shares
the documentation server's public origin, the server needs enough concurrent
request capacity to handle a token exchange while the callback is running.
A single-request worker cannot serve both sides of that exchange.

## Browser session and access checks

Sign-in uses state and S256 PKCE, with a ten-minute encrypted pending cookie.
Return navigation contains validated documentation version/page/resource fields
and an optional bounded fragment, rather than an arbitrary return URL. Callback
errors offer a retry without exposing provider responses or exception details.
Successful callbacks redirect promptly to a clean documentation URL.
Failed, cancelled and replayed callbacks consume pending state and preserve an
existing authenticated documentation session.

Authenticated cookies contain only the access token, expiry and logout CSRF
nonce. ActiveSupport MessageEncryptor protects them with AES-256-GCM and JSON;
separate purposes bind pending and authenticated cookies to the client, callback
and API mount. Cookies are Secure, HttpOnly, SameSite=Lax, mount-scoped and have
no Domain attribute. Complete cookies are limited to 3800 bytes; oversized token
responses fail sign-in rather than producing truncated sessions. Browser storage
used for documentation preferences never contains tokens.

Only HTML documentation GET handlers may use this cookie, and only on the
configured HTTPS origin. API actions, OPTIONS descriptions and mutations keep
their ordinary authentication. Explicit request credentials take precedence,
including malformed or conflicting credentials; a cookie does not repair them.
Each page revalidates the bearer token through the requested version's ordinary
providers and post-authentication hooks before describing resources. Identity and
roles are never taken from a cached user ID in the cookie. A revoked or expired
session returns to the public view; an inaccessible selected resource is 404.

Account controls follow the authentication actually used for that page. With
cached HTTP Basic credentials for one user and a documentation cookie for another,
the explicit Basic identity and its permissions take precedence. OAuth cookie
sign-out and Switch user controls are hidden in that mode. The legacy Basic
sign-out link cannot promise that a browser will erase cached credentials; use
a fresh browser context for OAuth account switching. Malformed or conflicting
explicit credentials do not fall back to the documentation cookie.

Personalized HTML and authentication responses use private, no-store caching and
`Referrer-Policy: no-referrer`. Configure access and error logs so callback query
strings, tokens, passwords and client credentials are not retained.

## Sign-out and recovery

Sign-out is a same-origin POST with a session-bound CSRF nonce. The server
attempts access-token revocation and clears local authenticated and pending
cookies. If revocation fails, the response states that local sign-out succeeded
but the server session may remain until expiry. It does not claim a successful
revocation, queue tokens for retry, or request a whole-account SSO sign-out.

When `switch_user: true`, readers authenticated by a documentation cookie see
Switch user in the Account menu. It submits the existing same-origin,
CSRF-protected logout POST
with one URL-encoded scalar `switch_user=1`. Disabled, duplicate, array and other
invalid switch fields, explicit credentials, or invalid origin/CSRF are rejected
before sign-out or revocation. Ordinary Sign out sends no switch field.

After successful local sign-out and revocation, switching returns 303 to the
fixed documentation login route for the default version. That login creates new
state and PKCE values; the old pending attempt and session are cleared. No return
URL or scope supplied by the switch request changes that destination. Cancelling
the new authorization leaves the old documentation session signed out. A revoke
failure retains the 502 response described above and does not continue to login.
Switching does not sign out of the provider's whole-account SSO session.

To disable this feature, remove its optional configuration before starting older
documentation code. Existing API data needs no migration or rollback. Cookies
expire or are ignored. Disable or revoke the dedicated OAuth client through
normal provider administration when needed; documentation rollback does not
delete clients automatically. APIs without this configuration retain their
existing sign-in controls.
