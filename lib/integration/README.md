# E4-final integration scaffold

This directory is the **E4-final** (flutter-e4, DAG wave 16) integration layer:
the seam where the final Flutter assembly wires the accepted diene Dart package
surface (`lib/dart/e2e`) and the observability payload onto the frozen
flutter-base app shell.

It is deliberately **additive** — it does not modify any frozen flutter-base file
(preserving accepted evidence at `891c5c9…`). It is committed in the
**SCAFFOLD COMPLETE — INTEGRATION HELD** state.

## What stands live now

- **`observability_wiring.dart`** — projects the observability payload's **LPSM**
  label model (landscape / platform / service / module, + version) from the app's
  own `AppIdentityConfig`, and binds it to a pluggable `SignalSink`. This needs
  only flutter-base + the `observability` payload (state: **done**), so it is
  wired live, not held. The concrete OTel / Grafana Faro exporter transport is
  the one held seam here (`SignalSink` / `heldSignalTransportReason`); a
  `NoopSignalSink` keeps the app buildable until the exporter lands with e2e.

## What is held (awaiting an accepted `lib/dart/e2e` sha)

`e4_manifest.dart` is the machine-checkable map (asserted by
`test/integration/e4_scaffold_test.dart`) of every point that swaps a flutter-base
local optimistic bridge for the real diene package delivered via `lib/dart/e2e`:

| flutter-base local bridge | diene package (via e2e) |
| --- | --- |
| `lib/core/result.dart` | `diene_result` |
| `lib/core/problem_catalog.dart` + `local_error.dart` | `diene_problems` |
| `lib/config/app_config.dart` loaders | `diene_config` + `diene_core_utils` |
| `lib/auth/*` gateways + session controller | `diene_auth_engine` |
| `lib/generated/service/**` | `diene_api_engine` |

## Primary hold reason

`lib/dart/e2e` has **no accepted sha yet** (state: `blocked`, under a fresh
sibling controller). The diene package surface it assembles cannot be wired until
that sha is independently ACCEPTED. Forcing the swap now would fabricate an
integration against an unaccepted parent — forbidden under the Turn-052 GO
OPTIMISTIC ruling (implement only against accepted/frozen sha).

## T13-REBASE plan (when e2e lands)

1. Rebase this branch onto the corrected parent sha; log `AUTO T13-REBASE`.
2. Add the accepted diene packages to `pubspec.yaml` (path/hosted deps).
3. For each held row above: replace the local bridge, clear its `held` flag in
   `e4_manifest.dart`, and delete the superseded local bridge file.
4. Swap `NoopSignalSink` for the real OTel/Faro exporter from the e2e telemetry
   surface (call sites are unchanged — they go through `ObservabilityContext`).
5. `e4IntegrationComplete` flips to `true`; the manifest test enforces it.
6. Independent (different-account, different-vendor) review of the real
   integration, then the normal T4 gates.

Until then: **no push, PR, publication, proof, release, tag, or provider
admission** — none is authorized by this ruling.
