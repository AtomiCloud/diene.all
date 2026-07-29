---
name: diene-dotnet-e2e-usage
description: Use AtomiCloud.Diene.E2e for in-process or Garden SIT and its published TestHelper bundle.
---

# Diene .NET E2e usage

- Set `SIT_DRIVER` explicitly to `inprocess` or `garden`; never infer the venue.
- Use `InProcessSitDriver<TEntryPoint>` for an ASP.NET entry point. Requests
  still cross the real application pipeline.
- Build Garden URLs with `GardenPreviewEndpoint.Resolve` and a matching
  `GardenNamespaceFixture`. The final hostname order is
  `module.service.platform.instance.landscape.zone`.
- Reference `AtomiCloud.Diene.E2e.TestHelper` only from tests. It bundles Result,
  Interfaces, Config, Problems, Otel, AuthEngine, StandardConfig, ApiEngine, and
  ServerEngine TestHelpers. CoreUtils has no TestHelper.
- Use StandardConfig's helpers for Testcontainers and always dispose containers.
- Use Interfaces/Otel in-memory seams for integration telemetry. Preview SIT
  rides the real Alloy pipeline; do not add a fake OTLP collector here.
- Keep Bruno under the service-side `tests/sit/bruno` path. This package is
  Bruno-free.

Use `ShouldHaveStatus` when an exact status is the contract. Continue inspecting
the returned response when body or header semantics matter.
