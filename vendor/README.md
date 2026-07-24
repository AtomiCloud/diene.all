# vendor/

Temporary local bridge for the not-yet-published upstream dependency.

`atomicloud-diene.config-1.0.0.tgz` is the certified `bun pm pack` artifact of
`@atomicloud/diene.config` at branch tip `564a2a9` (the exact tree whose Pr/CI
columns are done). It is vendored here ONLY because the real npm publish of
`@atomicloud/diene.config` is blocked on the privileged mirror flow
(`AtomiCloud/diene.bun-config` does not exist yet; fork-account controllers lack
AtomiCloud org publish rights) — see the config controller's escalation and this
node's inbox note.

The `overrides` entry in `package.json` redirects `@atomicloud/diene.config`
resolution to this tgz for THIS repo's dev/CI installs only (root-only; ignored
when the package is consumed as a dependency). The declared peer/dev range stays
`^1.0.0`, so published consumers resolve config normally from npm once it lands.

When `@atomicloud/diene.config` is published to npm: delete the `overrides`
entry and this `vendor/` directory, then `bun install` to re-resolve from the
registry. `vendor/` is excluded from the published package (the `files`
allowlist ships only `dist` and `skills`).
