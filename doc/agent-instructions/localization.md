# Localization

Required procedure selected by the repository AGENTS.md. The rules retain their
repository scope and precedence. Paths and commands below are relative to the
repository root unless explicitly stated otherwise.

## Localization
- Edit HaveAPI framework and client translations only in `i18n/haveapi.yml`.
- Run `bundle exec rake i18n:update` after translation changes. This regenerates
  server Ruby locale files and package-local client catalogs for Ruby, PHP, JS,
  and Go clients.
- Do not edit generated locale/catalog artifacts directly. They contain a
  generated-file header and will be overwritten by `i18n:update`.
- Applications can localize action parameter labels/descriptions and
  `choices`/`include` labels by setting the server `parameter_i18n_scope` to
  the application root. HaveAPI looks up exact resource/action keys, then
  shared resource input/output keys, resource attributes, and shared
  `attributes.<name>` keys. Use `label_key`/`desc_key` only for explicit
  overrides.
