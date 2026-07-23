# Faro Frontend Variant

Faro is the O1 frontend path for Next.js and Flutter. It is not a fourth OTel
library: each frontend owns a thin initialization adapter around the supported
Grafana Faro SDK, an error-reporter adapter, and its consumer tests.

## Shared initialization contract

Both variants must:

1. Read a validated, config-driven enabled flag, collector target, sampling
   policy, and service-tree `app:` block.
2. Initialize exactly once after client-safe configuration is available.
3. No-op without network activity when disabled.
4. Fail visibly on invalid enabled configuration; never swallow initialization
   failures and silently pretend telemetry is active.
5. Attach the complete LPSM/version identity to every event, error, session,
   and span.
6. Route unexpected exceptions and `LocalError` Problems through the same
   reporter after the UI error boundary has classified/rendered them.
7. Redact secrets and use an explicit allowlist for user/context attributes.
8. Flush or drain through the platform lifecycle hook where the SDK supports
   it.

## Identity mapping

Use the Faro app metadata fields for the semantic-convention-compatible core:

| Service-tree value | Faro application field / attribute              |
| ------------------ | ----------------------------------------------- |
| service            | app name / `service.name`                       |
| platform           | app namespace / `service.namespace`             |
| version            | app version / `service.version`                 |
| landscape          | app environment + `deployment.environment.name` |
| module             | `atomi.module` custom/session attribute         |

Also attach `atomi.landscape`, `atomi.platform`, `atomi.service`,
`atomi.module`, and `atomi.version`. Do not derive identity from the browser
hostname, Flutter bundle id, or a user-entered value.

## Next.js scaffold

The consumer-owned module follows this responsibility split:

```text
src/lib/observability/
├── config.ts
├── faro.ts
├── faro-error-reporter.ts
├── FrontendObservability.tsx
└── index.ts
```

- `config.ts` adapts the composed client-safe config; it does not load files.
- `faro.ts` builds metadata/instrumentations and exposes idempotent init.
- `faro-error-reporter.ts` implements the application's Problem/error reporter.
- `FrontendObservability.tsx` is a client-only composition adapter that invokes
  init after the SSR-injected config is available.
- The barrel exports the supported surface only.

Use the official `@grafana/faro-web-sdk` and
`@grafana/faro-web-tracing` packages. The component must not catch-and-discard
SDK failures. The argon module is a shape seed, not a verbatim port: its
service-tree naming, one-time init, and error-reporter split survive; silent
failure handling and app-specific config do not.

### Web source maps

Source-map upload is Next.js-only O1 scaffolding and runs inline from the
`next.config.ts` webpack hook during the OpenNext build with
`@grafana/faro-webpack-plugin`.

- Instantiate the plugin only when runtime Faro and `client.faro.build.enabled`
  are both true.
- Require endpoint, app id, stack id, and the single build secret
  `ATOMI_CLIENT__FARO__BUILD__KEY` before the upload path can run.
- Read the key from the build environment immediately before the build. It must
  never enter YAML, generated client config, DefinePlugin payloads, the bundle,
  image, or build artifacts.
- The PR-side guard/dry-run is a consumer gate. One real resolved stack trace is
  proven once while building diene; it is not a shipped probe row.

## Flutter scaffold

The consumer-owned module follows the Flutter equivalent:

```text
lib/src/observability/
├── faro_config.dart
├── faro_bootstrap.dart
├── faro_error_reporter.dart
└── observability.dart
```

Use Grafana's verified-publisher `faro` Flutter package. Map `service` to
`appName`, `platform` to `namespace`, `version` to `appVersion`, and landscape
to `appEnv`; put the raw `atomi.*` taxonomy and
`deployment.environment.name` into session/resource attributes. Wrap the app
once through the SDK bootstrap and add only the approved interaction/asset
instrumentation widgets.

Flutter does not reuse the web webpack source-map uploader. Native symbol and
source mapping remains a Flutter release-pipeline concern unless its owning
goal explicitly adds a contract.

## Consumer-owned proof

Next.js and Flutter each own gates for disabled no-op, exactly-once init,
complete LPSM metadata, and error propagation. Next.js separately owns the
source-map upload guard. Live collector/export paths and environment-specific
targets remain outside this payload node.
