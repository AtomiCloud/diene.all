# Typed problem contract

<!-- ### lib-dotnet-problems -->
<!-- #### source: lib/dotnet/problems -->

`AtomiCloud.Diene.Problems` owns the portable typed-problem contract and the
framework boundary that renders it. A consumer owns its domain problem classes,
registers them explicitly, and uses the resulting catalog as the single runtime
and export source of truth.

## Scope

| Surface                        | Responsibility                                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `IDomainProblem` and `Problem` | Separate typed domain data from the RFC 9457 wire envelope and its `data` and `recoverable` extensions.             |
| `ProblemTypeUriBuilder`        | Build the only supported versioned type URI from plain ErrorPortal and LPSM values.                                 |
| `ProblemCatalogBuilder`        | Register typed problems, statuses, recoverability, and affected endpoints explicitly.                               |
| Baseline catalog               | Supply seven portable problems with snake_case wire ids and default status policy.                                  |
| `ProblemExporter`              | Derive payload JSON Schema from the .NET serialization contract with the BCL exporter.                              |
| `ProblemResourceEmitter`       | Emit one deterministic `atomi.cloud/v1alpha1` Problem resource for one catalog version.                             |
| `ProblemGuard` and adapters    | Carry expected failures in `Result<T, IDomainProblem>` and convert them to exceptions only at framework boundaries. |
| ASP.NET Core adapter           | Register `IExceptionHandler`, `AddProblemDetails`, and RFC 9457 rendering through `AddAtomiProblems`.               |
| TestHelper                     | Assert typed identity, exceptions, Results, envelopes, and full HTTP responses.                                     |

## Runtime rules

Registration is mandatory. A type that is absent from the catalog, or an object
that spoofs a registered `(version, id)` with the wrong concrete type, is treated
as an internal catalog-loop failure: the response status is 500, its type is
`about:blank`, and `ProblemCatalog` logs an error. A missing registration must
never silently become a consumer-visible 4xx response.

Wire ids are snake_case and versions use the `v1` form. Their exact patterns are:

```text
id: ^[a-z][a-z0-9_]*$
version: ^v[0-9]+$
```

The canonical URI shape is:

```text
{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}
```

Only `IProblemTypeUriBuilder` may expand that shape. Consumers, controllers, and
other engine libraries inject the builder instead of copying the template.

Problem metadata (`id`, `title`, `detail`, and `version`) is excluded from typed
payload serialization. The HTTP envelope carries the RFC 9457 members plus the
serialized payload in `data`, the catalog policy in `recoverable`, and arbitrary
extensions such as `traceId`.

## Catalog and Problem resources

Each service registers its baseline and domain-specific problems in its
composition root. `ProblemExporter` derives the payload schema using
`System.Text.Json.Schema.JsonSchemaExporter` and lifts `DescriptionAttribute`
values into schema descriptions. `ProblemResourceEmitter` validates portal
identity, catalog version, and exported type URI before producing canonical JSON
that is valid YAML 1.2.

The consuming service owns the build task that writes emitted resources into its
primordial chart. This package owns the model and emitter, not that repository
task or chart layout.

## Removed template warts

| Previous behavior                                                 | Current rule                                                                     |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Assembly and namespace scanning selected problems implicitly.     | Registration is consumer-owned; assembly scanning is opt-in and caller-filtered. |
| A hard-coded API route exposed error metadata at runtime.         | Catalog data moves through the Problem custom-resource channel.                  |
| Unknown problems silently fell back to a 4xx response.            | Unknown or spoofed typed problems log loudly and return 500.                     |
| Multiple adapters formatted problem type URIs.                    | One injected builder owns URI construction.                                      |
| The sample coupled integration tests to Redis and Testcontainers. | The integration tier exercises ASP.NET Core in process.                          |

## Deliberately absent

- No runtime error-info controller or catalog endpoint.
- No dependency on a configuration package; composition roots map their own
  settings into `ErrorPortalOption` and `ProblemIdentity`.
- No server-engine or application hosting policy beyond the problem exception
  adapter.
- No implicit global catalog and no custom per-instance recoverability override.
