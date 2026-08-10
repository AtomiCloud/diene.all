---
name: diene-problems-usage
description: Declare, emit, transform, and test RFC 9457 Problems with @atomicloud/diene.problems.
---

# Diene Problems usage

Read `docs/standards/problems/index.md` before changing a Problem contract.

- Create one `ProblemRegistry` from the configured `ErrorPortalConfig`; never
  hand-format type URIs.
- Use `createGenericProblemRegistry` or `registerGenericProblems` for
  ValidationError, EntityNotFound, and Unauthorized. Register domain Problems
  only in the consuming service.
- Declare endpoint/recoverability metadata with `ProblemCatalog`, then emit the
  committed primordial-chart row with `emitProblemResource`.
- Transform unknown errors with `ProblemTransformer`; keep HTTP-to-`Result`
  bridging in `@atomicloud/diene.api-engine`.
- In tests, import `expectProblem`, `buildProblem`, and
  `buildProblemFromRegistry` from `@atomicloud/diene.problems/test-helper`.
