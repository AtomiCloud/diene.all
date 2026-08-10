# Core utilities

<!-- ### lib-dotnet-core-utils -->
<!-- #### source: lib/dotnet/core-utils -->

`AtomiCloud.Diene.CoreUtils` is a pure value library. It has no IO, no state, and
nothing to configure. Membership is deliberately narrow: a helper only ships here
if .NET lacks a native or LINQ answer.

## What is in scope

| Member                                | Why it exists                                                                                                                     |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `Wire` + `AtomiJson` converters       | The C0 §1 serialization contract — one spelling of every date, time, instant, duration, timezone, decimal, and int64 on the wire. |
| `Slug.Slugify` / `Slug.NamespacedKey` | Identifiers derived in C# must equal identifiers derived in TypeScript, Go, and Dart.                                             |
| `KeyNormalizer`                       | The one canonical key-matching rule; consumed by the Config lib's YAML provider.                                                  |
| `WireAttributes`                      | Bridges the wire forms onto the `ILoggerSink` / `IMetricsCollector` attribute maps declared by `AtomiCloud.Diene.Interfaces`.     |

## What is deliberately absent

Deep-merge and env-var→nested-path coercion are NOT ported from the TypeScript
sibling. `IConfiguration` provider layering IS the merge, and the configuration
binder already owns `<Prefix>A__B` coercion with type conversion at bind time.
Porting them would re-implement the framework. The one thing the framework does
not do — separator-insensitive key matching — is `KeyNormalizer`.

`sleep`, `noop`, `unique`, `isRecord`, `fuzzyIncludes`, `mapWithConcurrency`,
`sha256`, and the `safeJoin` filesystem helpers are absent for the same reason:
`Task.Delay`, `DistinctBy`, `string.Contains(OrdinalIgnoreCase)`,
`Parallel.ForEachAsync`, `SHA256.HashData`, and `Path.GetFullPath` already do
them, and wrapping the BCL earns nothing.

## The wire contract

Domain code keeps native temporal types; only the transport sees strings. That
split is what ends the bespoke-format bug class the C0 spec was written against
(`ZincDate`'s DD-MM-YYYY, and locale-formatted dates crossing service
boundaries).

| Domain type      | Wire form              | Notes                                                                                                                         |
| ---------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `DateOnly`       | `2026-07-25`           | Strict; `2026-7-25` is rejected.                                                                                              |
| `TimeOnly`       | `17:30:00`             | Whole seconds; formatting truncates, parsing rejects a fraction.                                                              |
| `DateTimeOffset` | `2026-07-25T22:30:00Z` | Always emitted as UTC `Z`. Parsing accepts an offset and normalizes it, and truncates fractional digits below tick precision. |
| `TimeSpan`       | `PT1H30M`              | Time components plus whole days. `P1Y`, `P1M`, and `P1W` are rejected — no fixed length.                                      |
| `TimeZoneInfo`   | `Asia/Singapore`       | IANA ids only, resolved against the host database. Windows ids and bare offsets are rejected.                                 |
| `decimal`        | `"1249.50"`            | A string. Money is never a float.                                                                                             |
| `long`           | `"9007199254740993"`   | A string, globally. Past 2^53 a JSON number loses precision in every JavaScript peer.                                         |

Reading a `decimal` or `long` still accepts a JSON number so that a peer which
has not adopted the contract degrades rather than fails. Writing never does.

Canonical values are pinned in `fixtures/c0/wire-v1.json` and asserted by both
the unit tier (round-trip) and the integration tier (host IANA database, real
filesystem read). Changing a pinned value is a cross-language contract change.

## Failure model

Parsing is total. Every codec returns `Result<T, WireFormatError>` and slug
composition returns `Result<string, KeyError>`; neither throws for a rejected
payload. The System.Text.Json converters are the one exception, and only because
System.Text.Json requires `JsonException` as its failure channel.

## Test tiers

- **unit** — 100% of the shipped assembly, including the pinned C0 fixture
  round-trips and the cross-language slug and key tables.
- **int** — the parts that are only real against the host: IANA timezone
  resolution through the machine's tz database, and the fixture loaded off a real
  filesystem through the demo consumer in `App/`.
- **meta** — inactive. There is no TestHelper package; see the shipped
  `skills/diene-dotnet-core-utils-usage/SKILL.md` for the rationale and for how
  to add one if a real consumer need ever appears.
