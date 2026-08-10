# vendor/

No dependency artifacts are currently vendored.

The temporary `@atomicloud/diene.config` tarball bridge was retired after
`@atomicloud/diene.config@1.0.0` became available from the public npm registry.
The root-only `overrides` entry and certified tarball were removed, and
`bun.lock` now resolves the unchanged peer/dev range (`^1.0.0`) from npm.

This directory remains as a record of the bridge lifecycle. It is excluded from
the published package by the `files` allowlist, which ships only `dist` and
`skills`.
