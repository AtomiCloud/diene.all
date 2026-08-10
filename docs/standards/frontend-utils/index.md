# Frontend utilities

`@atomicloud/diene.frontend-utils` supplies the reusable frontend mechanisms
shared by browser, Worker, fully static, Next.js, and Flutter-shaped clients.
Its core entrypoints are React-free and safe to import during SSR. React
providers and hooks are explicit adapter subpaths.

## Module boundary

Define a module with a stable lowercase identifier, configuration surface, and
optional lifecycle. Register and resolve it through the provider-agnostic
registry. Missing and duplicate modules return typed Results.

The package intentionally exports no dependency-injection container and no
application wiring. Compose providers, engines, and modules in the consuming
template.

## Landscape accessor

Call `landscape()` with exactly one host-supplied source:

- a Worker/runtime binding for Next.js or OpenNext;
- a baked build-time constant for a fully static frontend; or
- a dart-define value for Flutter.

The accessor validates and returns that value, then
`landscapeConfigAnchor()` feeds it into `@atomicloud/diene.config`'s landscape
tier. It never reads a hostname, process environment, browser global, or other
detection surface. The canonical fixture set covers the seven workload
landscapes (`lapras`, `ditto`, `rotom`, `absol`, `eevee`, `plusle`, `minun`)
and the serving fixtures (`pichu`, `pikachu`, `raichu`).

## Content and problems

Use the content state machine for loading, error, empty, and content branches.
Errors always carry a Problem. Unknown thrown values become LocalError
Problems with a captured message and stack. Use the React binding to render
branches and the problem visualizer to provide a default plus type-specific
overrides.

## Theme

Theme utilities control CSS-variable values at runtime, persist selection, and
resolve system/light/dark or named themes. The consumer owns every token and
value. The package owns only resolution, switching, persistence, and a
dark-mode flag. Use the React subpath only at the component boundary.

## Discovery and rescue

Doc A is refreshed while foregrounded and lists catalog hosts. Doc B is read
only during sign-up for ping-and-pick home selection. Doc C is fetched only
inside a hard connect-failure rescue trip. Each document has an independent
monotonic version. Validate every used URL against the baked suffix allowlist;
keep the auth issuer baked outside documents.

The hot path retains one home hostname and retry-once network behavior. It
never consults discovery. The dormant router is enabled only for browser and
Flutter contexts, scans Doc C candidates in order with jitter and a fixed
budget, and persists its last-known-good endpoint without expiry. Next.js
server contexts disable it.

## UX mechanisms

Use the narrow `/urlstate`, `/persistence`, `/loader`, `/toast`, and `/a11y`
subpaths. URL changes use debounced `replaceState`; drafts clear on cancel,
close, submit, or reset; content loaders may debounce around 100 ms but button
spinners do not; toast is passive with at least five seconds of aria-live
dwell; safe-area and reduced-motion helpers carry no visual-token opinions.

## TestHelper

Import `/test-helper` only in tests. It provides the canonical landscape
builders, in-memory persistence, a pinned provider-wrapper harness, content
state builders, and an isolated module registry. Prefer these fakes so consumer
tests exercise the same contracts as production.
