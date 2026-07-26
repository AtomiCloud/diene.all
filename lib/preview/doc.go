// Package preview resolves the Garden preview environment a SIT run targets.
//
// SIT is the tier that runs against a REAL deployed environment, so the one
// thing the harness must never do is invent its address. Every setting arrives
// from the environment through the [interfaces.System] seam, and a missing
// setting is a typed refusal rather than a default that quietly points a test
// suite at localhost and passes.
//
// # What a target implies
//
// A [Target] is the preview environment's service-tree identity plus its
// addresses. From that one value the harness derives every engine block the
// system under test needs, so a SIT suite configures nothing twice:
//
//   - [Target.Identity] and [Target.AppBlock] — the LPSM identity (C0 §3).
//   - [Target.OtelConfig] — all three signals on and exporting OTLP
//     http/protobuf to the preview collector (D2). This is the SIT tier's job:
//     the integration tier proves emission against in-memory mocks and spins up
//     NO telemetry infrastructure (G1), and real export is proven here against
//     the Garden preview environment's alloy endpoint.
//   - [Target.AuthConfig] — the preview IdP's issuer, audience, and JWKS.
//   - [Target.APIConfig] — one api-engine backend pointed at the preview
//     service.
//   - [Schema] — the composed root schema those blocks validate against.
//
// # No Bruno
//
// Bruno orchestration is sample-side. This package resolves a target and hands
// back typed configuration; how a template chooses to drive HTTP against it is
// the template's business.
package preview
