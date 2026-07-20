---
name: diene-bun-lib-usage
description: Use the dual-format AtomiCloud Bun library package from ESM, CommonJS, or TypeScript.
---

# Diene Bun library usage

Import the public package surface; do not copy its implementation or reach into
`dist/` or `src/`. Use the ESM example in `assets/consumer.ts` or the CommonJS
example in `assets/consumer.cjs` as the smallest integration check.

This template does not ship a TestHelper because its sample surface needs no
consumer fake or repeated assertion helper. If a promoted library introduces
ports, nondeterminism, or repeated assertions, follow `assets/test-helper.md`
and expose the helper through the package's `/test-helper` subpath.

For build, package, release, and promotion rules, read
`docs/developer/bun-lib-baseline.md` in the source repository.
