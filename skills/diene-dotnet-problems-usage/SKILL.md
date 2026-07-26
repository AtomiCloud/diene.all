---
name: diene-dotnet-problems-usage
description: Use AtomiCloud.Diene.Problems and its TestHelper in .NET services. Use when defining, registering, rendering, exporting, or asserting typed RFC 9457 problems.
---

# Diene .NET Problems usage

Use the package as a registration-first problem boundary. Consumer services own
their domain problem classes; this library owns stable identity, catalog policy,
wire rendering, and export mechanics.

## Register the catalog

1. Implement `IDomainProblem` with a public parameterless constructor. Keep
   `Id`, `Title`, `Detail`, and `Version` metadata `[JsonIgnore]`d and expose only
   the typed payload to serialization.
2. Call `AddAtomiProblems` once in the composition root. Register `AddBaseline()`
   and every consumer problem with status, recoverability, and affected
   `ProblemEndpoint` values.
3. Add `UseExceptionHandler()` to the ASP.NET Core pipeline.

Never rely on implicit scanning. `AddFromAssembly` is allowed only as an explicit,
caller-filtered registration choice.

## Preserve the single URI source

Resolve and call `IProblemTypeUriBuilder` for every problem type URI. Never format
or copy the ErrorPortal URI template in a controller, transformer, test, or other
library. Wire ids are snake_case and versions use the `v1` form.

## Carry and render failures

Use `ProblemGuard` or `ToErr<T>()` while a failure remains expected domain data.
Use `ToException()` only at a framework boundary. An unregistered or type-spoofed
problem is a catalog defect: preserve the library's logged 500 behavior instead
of adding a fallback status.

## Assert contracts

Reference `AtomiCloud.Diene.Problems.TestHelper` only from test code. Assert
domain identity with `BeProblem<T>()`, `HaveId`, and `HaveVersion`; Result errors
with `BeErrProblem<T>()`; and HTTP responses with `BeRfc9457`, `HaveType`,
`HaveStatus`, `HaveData`, and `BeRecoverable`. Prove new assertions with both a
known-good and known-bad meta test.

## Export Problem resources

Resolve `ProblemResourceEmitter` from the same registered service provider. Emit
one resource per platform/service/landscape/version row and let the consuming
service's build task write the serialized canonical JSON/YAML into its chart.
