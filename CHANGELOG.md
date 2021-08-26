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
