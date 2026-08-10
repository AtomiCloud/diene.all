---
name: diene-e2e-usage
description: Use when consuming @atomicloud/diene.e2e, its ten-member Bun version train, member subpaths, bundled test helpers, Garden preview endpoints, or Bruno environments.
---

# Using `@atomicloud/diene.e2e`

Use this as the one dependency for the ten-member Bun train: result,
interfaces, core-utils, config, problems, otel, auth-engine, api-engine,
standard-config, and frontend-utils.

- Import common `Result`, `Option`, `Problem`, `ConfigRegistry`, and `initOtel`
  identities from the root.
- Import a broad API through `/<member>`; use `/auth` and `/api` for the two
  engine packages.
- Import e2e glue and frozen helper namespaces from `/test-helper`.
- Import one member helper through `/<member>/test-helper`. Helpers exist for
  every member except core-utils.
- Use `resolveGardenPreviewEndpoint` with the final dotted instance hostname
  and the matching namespace fixture. HTTPS is the default.
- Use `createBrunoEnvironment` for a Bruno collection's string variables.
- Use standard-config container start helpers only in integration tests and
  stop every container in `finally`. Telemetry tests use the otel/interface
  in-memory seams, never a collector.

The train uses manual tilde-bound dependency commits: result `~1.0.2`, all
other members `~1.0.0`. Depend directly on one member only when the package
genuinely needs that member alone or publishes its types.

R-E12 transfers this skill and standard downstream through package installation
and skills-sync; member skills remain owned by their packages. R-E22's former
standard-config bridge was build/test-only and is now retired because registry
1.0.0 is live. The manifest and lock must remain registry-backed.
