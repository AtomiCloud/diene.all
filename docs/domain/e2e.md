# .NET e2e harness contract

The harness has two explicit venues:

- `inprocess` preserves ASP.NET routing, middleware, model binding, and response
  serialization through `WebApplicationFactory`;
- `garden` reaches a deployed service through the final
  `module.service.platform.instance.landscape.zone` hostname.

`SIT_DRIVER` is mandatory. A missing selector is not interpreted as either
venue because a result with an unknown execution boundary is not reusable
evidence.

Garden endpoint resolution validates the hostname and every namespace
coordinate, permits only HTTP(S), bounds ports to 1–65535, and requires an
absolute URL path. The fixture match prevents a test meant for one
service-tree instance from quietly reaching another.

The TestHelper package bundles the nine published helper packages through
normal NuGet dependencies. It does not wrap, fork, or copy their public APIs.
CoreUtils has no helper by design. StandardConfig remains the only home for
Testcontainers infrastructure glue, and telemetry tests use the Interfaces and
Otel in-memory seams rather than a fake collector.

Bruno is intentionally absent. API collections are service/product tests and
remain in the `dotnet-api` template.
