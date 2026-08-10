# Faro source-map traceability — design-time proof (Q-G18)

Proven ONCE while building diene, per the STEP5-REVIEW-LEDGER Q-G18 ruling
("test till it works"): a real thrown error's stack resolves from the minified
production bundle back to source through the same source maps the
`@grafana/faro-webpack-plugin` upload step ships. There is NO ongoing scaffold
probe and NO credential distribution for this — the mechanism is assumed to
keep working from here on.

## What was run (2026-07-25, controller session mrzz9a3h-d084df92)

1. `next build` with `productionBrowserSourceMaps: true` (the same build the
   OpenNext rail consumes; the faro plugin uploads these exact maps in the
   Layer C job).
2. The standalone server booted the REAL production bundle; a Playwright
   browser poisoned `history.replaceState` and typed into the url-bound
   search bar, so the app's own debounced handler threw
   `Error: faro-trace-proof` from inside minified code.
3. The captured stack frame was resolved with the `source-map` consumer
   against the build's emitted `.map` files.

## Evidence

Minified frame (as faro would receive it):

```text
at Object.replaceState (…/chunks/app/%5Blocale%5D/page-9546d933a86d97a4.js:1:4481)
```

Resolved through the build's own source map:

```text
page-9546d933a86d97a4.js:1:4481
  -> webpack://_N_E/src/adapters/hooks/useUrlState.ts:31:27 (replaceState)
```

That is the exact source call site (`window.history.replaceState(...)` inside
`useUrlState`'s history port) — resolution reaches original TypeScript source,
not a minified alias. Deeper frames resolved into the published lib's dist
(`@atomicloud/diene.frontend-utils/dist/urlstate.js:46`), which is the correct
boundary: the lib ships its own maps upstream.

## Wiring summary (Layer B / Layer C)

- PR CI (Layer B, no creds): the OpenNext build job runs with
  `ATOMI_CLIENT__FARO__BUILD__KEY` absent, so the upload plugin is skipped —
  the build itself dry-runs the source-map generation this proof used.
- Pre-release (Layer C, creds): `⚡reusable-upload.yaml` injects the key right
  before `opennextjs-cloudflare build`; the plugin uploads the maps and the
  key never persists into the artifact.
