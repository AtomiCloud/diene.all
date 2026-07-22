---
name: diene-go-core-utils-usage
description: Use Diene Go deterministic core utilities for keys, configuration values, timing, and C0 temporal wire forms.
---

# Diene Go core utilities usage

Import `github.com/AtomiCloud/diene.go-core-utils/lib/coreutils` for pure,
deterministic helpers. Use `Slugify` and `NamespacedKey` for stable identifiers;
handle a `NamespacedKey` error with `errors.As` as a `problem.Error` when a
caller needs its C0 validation envelope.

- Use `DeepMerge` and `EnvironmentToNestedMap` for configuration values only.
  Environment nesting is `__`; lists are contiguous zero-based indexed keys.
  Do not decode JSON or comma lists from environment values.
- Keep money and other exact decimals as strings. `CoerceEnvironmentScalar`
  deliberately produces `float64` only for ergonomic configuration numerics.
- Use `WireCodec`, `WireDate`, `WireTime`, `IsoDuration`, and `IanaTimezone`
  for C0 wire boundaries. Instants are always canonical RFC 3339 UTC `Z`.
- Use `Sleep(ctx, duration)` so cancellation reaches timing work.

## Future TestHelper criterion

This module intentionally has no `testhelper`: stock equality is sufficient for
its pure deterministic API. Add one only if a future public API creates a real
consumer seam to fake or a repeated nontrivial assertion. Keep it dependency
light, add black-box meta tests and active meta coverage, and never expose
private production logic only for tests.
