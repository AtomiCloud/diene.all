---
name: diene-frontend-utils-usage
description: Integrate @atomicloud/diene.frontend-utils in web, Next.js, Workers, static, or React applications. Use when choosing its module, landscape, content, theme, discovery, URL-state, persistence, loader, toast, a11y, or TestHelper subpaths; when replacing copied frontend spine code; or when checking the package's no-DI, SSR-safety, and React-boundary rules.
---

# Diene Frontend Utils Usage

Use the narrowest public subpath. Keep application wiring in the consumer and
keep React imports in explicit React binding subpaths.

## Select a subpath

- `/module`: module definitions and provider-agnostic registration/resolution.
- `/landscape`: read a host-supplied binding, baked constant, or dart-define.
- `/content` and `/content/react`: loading/error/empty/content state and UI.
- `/theme` and `/theme/react`: CSS-variable theme mechanics and bindings.
- `/discovery`: edge documents and the dormant hard-failure rescue path.
- `/urlstate`, `/persistence`, `/loader`, `/toast`, `/a11y`: mechanism-only UX
  primitives without visual tokens.
- `/test-helper`: canonical landscape fixtures, in-memory persistence, pinned
  harnesses, content states, and fake module registries.

Import types and functions only from package exports. Never deep-import
`dist/` or `src/`.

## Preserve the boundaries

- Supply the landscape explicitly. Never derive it from hostname, globals, or
  environment variables inside application code.
- Build DI wiring and containers in the application/template. This package
  provides contracts and resolution primitives only.
- Import React adapters only from `/content/react` or `/theme/react`; core
  entrypoints must remain usable in Node and server runtimes.
- Keep discovery off the hot path. Ordinary calls retain one home hostname and
  retry once on network failure. Wake rescue only for a hard connect failure.
- Fetch Doc B only for sign-up selection and Doc C only inside a rescue trip.
  Keep the baked auth issuer outside every discovery document.
- Use toast only for passive notices; render errors in content/problem UI.
- Keep token authorship in the consumer. Theme and a11y exports are mechanisms.

## Test consumers

Prefer `/test-helper` rather than rebuilding fakes. Pin a landscape source and
theme persistence explicitly, then exercise consumer wiring. Do not use the
helper from production entrypoints.

Copy [consumer.ts](assets/consumer.ts) for a core integration outline and
[consumer-test.ts](assets/consumer-test.ts) for a TestHelper outline; adapt the
application-specific identifiers and rendering layer.
