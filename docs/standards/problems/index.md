# RFC 9457 Problems

`@atomicloud/diene.problems` owns the Bun family’s Problem Details machinery.
HTTP-to-`Result` bridging belongs to `@atomicloud/diene.api-engine`; services
must not recreate it here or expose runtime error-info reflection endpoints.

## Envelope

A `Problem<TData>` carries RFC 9457’s `type`, `title`, `status`, optional
`detail` and `instance`, plus the required typed `data` extension. Define the
payload with Zod and register the definition in a `ProblemRegistry`. Creating a
Problem parses `data` through that same schema.

## Versioned type identity

Construct a registry from the service’s `ErrorPortalConfig`. It contains the
scheme, host, landscape, platform, service, and module values supplied by
configuration. Registration calls the one URI builder in `src/lib/uri.ts` and
adds the definition’s version and id. Never format a type URI in consumer code.

Versions use `vN`. A new version deliberately creates a new Problem contract
identity; never mutate an already-published version’s meaning.

## Registry and generic catalog

The registry is the enumerable publication source. Domain Problems belong in
the consuming service. This package provides only the portable
`ValidationError`, `EntityNotFound`, and `Unauthorized` definitions through
`registerGenericProblems` and `createGenericProblemRegistry`.

## Publication paths

`emitProblemManifest` produces a deterministic list plus JSON Schema keyed by
each registered type URI. `ProblemCatalog` adds the per-service fields:
`recoverable` and `endpoints`. The declaration keeps its JSON Schema in `data`,
matching C0’s edge catalog shape.

`emitProblemResource` writes one Kubernetes `Problem` resource for a
platform/service/landscape/version row. The canonical CR stores that same
payload schema under each `spec.problems[].schema` field. Commit generated rows
to the service’s primordial chart and drift-check them in CI. Erbium merges
rows and publishes the edge catalog; frontends consume that edge copy and
never call Primordial.

Uncatalogued failures remain 5xx-class failures and feed the catalog update
loop. The next service release adds the declaration, re-emits its row, and lets
erbium republish it.

## TestHelper

Import `expectProblem`, `buildProblem`, and `buildProblemFromRegistry` from
`@atomicloud/diene.problems/test-helper`. `expectProblem(actual).toBe(entry)`
checks type, title, status, and the registered Zod data schema. Optional
expectations add exact detail, instance, status, and data comparisons. The
helper has no test-framework runtime dependency.
