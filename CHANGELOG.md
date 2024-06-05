# Wed Jun 05 2024 - version 0.23.2
## Ruby server
- Another fix token auth renewal

# Wed Jun 05 2024 - version 0.23.1
## Ruby server
- Fix token auth renewal

# Fri Apr 19 2024 - version 0.23.0
## Ruby server
- Add mount hooks to `HaveAPI::Server`, allowing the developer to register custom Sinatra endpoints
- Fix Ruby client example generation

# Thu Mar 14 2024 - version 0.22.0
## PHP client
- Add option to send custom query parameters to the OAuth2 authorization
  request and token revocation endpoint

# Fri Feb 16 2024 - version 0.21.0
## Ruby server, Ruby client and Golang client generator
- Introduce RuboCop and fix offenses
- Require Ruby 3.2

## PHP client
- Introduce PHP CS Fixer and apply fixes

## PHP client

# Sun Jan 21 2023 - version 0.20.0
## Ruby server
- Require ActiveSupport and ActiveRecord >= 7.1
- Fix boolean input parameter conversion on Ruby 3.2

## All clients
- Path parameters can contain numbers

## PHP client
- Set Client-IP HTTP header on OAuth2 requests

## Golang client generator
- Fix ERB deprecation warnings
- Support for OAuth2 access tokens

# Wed Dec 27 2023 - version 0.19.0
## Ruby server
- Fix OAuth2 token grant check
- Support for OAuth2 code challenge verification
- Support for OAuth2 token revocation
- Improve OAuth2 documentation by adding client examples
- Configurable OAuth2 URL in case it should differ from API URL
- Replace OAuth2 `render_authorize_page` with `handle_get_authorize` to allow the GET endpoint to authorize the client
- Global action pre-authorization hook
- Authorization blocks have access to path parameters
- Define scopes for all actions based on resource and action name
- Add scope to default input parameters for token authentication
- Support for custom OAuth2 HTTP header with access token
- Setup output formatter only on JSON endpoints

## Ruby client
- Do not prompt for optional authentication parameters on standard input
- Improved exception output by hiding long instance variables from `#inspect`

## PHP client
- Support for OAuth2

## JavaScript client
- Support for accessing API with OAuth2 access token

# Sat Dec 02 2023 - version 0.18.0
## Ruby server
- Support for OAuth2 authorization provider

# Sun Sep 24 2023 - version 0.17.0
## Ruby server
- Pass exceptions from Action.safe\_output to exec\_exception hook
- Sinatra 3.0
- Improve compatibility with Ruby 3.0
- Use correct credentials for token auth examples in online documentation
- Use option `user` instead of `username` in HTTP basic authentication examples
- Updated dependencies

## Ruby client
- Updated dependencies
- Use CLI option `--user` instead of `--username` for HTTP basic authentication

## PHP client
- Compatibility with PHP 8.1
- Switch to vpsfreecz/httpful
- Use option `user` instead of `username` for HTTP basic authentication

## JavaScript client
- Use option `user` instead of `username` for HTTP basic authentication

# Thu May 5 2022 - version 0.16.0
## Ruby server
- Sinatra 2.2.0, ActiveRecord >= 6.0

## Ruby client
- Fix action invocations in CLI
- Sort resources, actions and parameters by name

## Go client
- Sort resources, actions and parameters by name
- Use go fmt on the generated code
- Support for sending resource parameters as nil

# Mon Dec 27 2021 - version 0.15.0
## Ruby server
- Improved compabitility with Ruby >= 3.0
- Input parameter options are given as keyword arguments
- Input parameter restrictions (`restrict() and ``with_restricted()`) accept
  only keyword arguments
- `HaveAPI::Hooks` supports keyword arguments

## Ruby client
- Action input parameters can be given either as a hash using a positional
  argument, or keyword arguments, but not both
- `HaveAPI::Response#wait_for_completion` now accepts keyword arguments
- `HaveAPI::Client#authenticate` now accepts keyword arguments

## PHP client
- Requires PHP >= 7.4
- Updated dependencies

# Thu Aug 26 2021 - version 0.14.0
## Ruby server
- Updated dependencies
- Do not coerce types of nil output parameters

## Ruby client
- Updated dependencies
- Parse error message when the server returns bad request
- Do not fail prematurely if the token expired, try it
- Fix Action#unresolved\_args? to check for path parameters using curly brackets

## PHP client
- Token authentication
  - Add methods `isComplete()` and `getResource()`
  - Fix `checkValidity()` to check for custom action credentials
  - Authentication callbacks get description of action credential parameters
    in addition to their names

# Thu May 16 2019 - version 0.13.0
- Protocol version set to 2.0, making it incompatible with previous versions
- Redesigned token authentication now supports multi-step authentication
  processes and custom credentials
- Action `url` and `url_params` in API description were renamed to `path`
  and `path_params`
- Action path parameter variables use curly brackets instead of colons
- New client generator for Go

## Ruby server
- Added support for fully dynamic resources and actions
- New exception `HaveAPI::AuthenticationError`
- Proper coercion of typed output parameters

# Thu Mar 07 2019 - version 0.12.0
## All
- Unified changelog file

## Ruby server
- Authorization and parameter filtering for action examples
- Update sinatra to v2.0, tilt to v2.0 and require\_all to v2.0

## Ruby client
- Update require\_all to v2.0

# See changelogs of previous versions in respective client/server directories
