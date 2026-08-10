---
name: diene-dotnet-core-utils-usage
description: Put dates, times, durations, timezones, decimals, and int64s on the wire in C0 form, compose slug identifiers, and match config keys across casings with AtomiCloud.Diene.CoreUtils.
---

# Diene .NET core-utils usage

## What this package is

`AtomiCloud.Diene.CoreUtils` is a pure value library. It holds the three things
the .NET family could not get from the BCL:

1. **Wire codecs** for the C0 §1 serialization contract — the one spelling of
   every date, time, instant, duration, timezone, decimal, and 64-bit integer
   that crosses a service boundary.
2. **Slug and namespaced-key helpers**, byte-parity with the sibling
   `@atomicloud/diene.core-utils` `slugify`, so an identifier derived in
   TypeScript and one derived in C# are the same string.
3. **`KeyNormalizer`**, the canonical key-matching rule the Config lib's YAML
   provider uses.

Nothing here does IO, holds state, or needs configuring.

## Wire formats — use `AtomiJson`, not attributes

Register the options once and every value in the payload obeys the contract.

```csharp
using AtomiCloud.Diene.CoreUtils.Json;

var json = JsonSerializer.Serialize(receipt, AtomiJson.DefaultOptions);
var back = JsonSerializer.Deserialize<Receipt>(json, AtomiJson.DefaultOptions);
```

Wiring it into an ASP.NET host:

```csharp
builder.Services.ConfigureHttpJsonOptions(o => AtomiJson.Apply(o.SerializerOptions));
builder.Services.AddControllers().AddJsonOptions(o => AtomiJson.Apply(o.JsonSerializerOptions));
```

`DefaultOptions` is read-only. Adding a converter to it throws — that is
deliberate, so one caller cannot change how every other caller serializes. Build
your own `JsonSerializerOptions` and call `Apply` when you need extras.

| Domain type      | Wire form              | Converter                |
| ---------------- | ---------------------- | ------------------------ |
| `DateOnly`       | `2026-07-25`           | `WireDateConverter`      |
| `TimeOnly`       | `17:30:00`             | `WireTimeConverter`      |
| `DateTimeOffset` | `2026-07-25T22:30:00Z` | `WireInstantConverter`   |
| `TimeSpan`       | `PT1H30M`              | `WireDurationConverter`  |
| `TimeZoneInfo`   | `Asia/Singapore`       | `WireTimeZoneConverter`  |
| `decimal`        | `"1249.50"`            | `DecimalStringConverter` |
| `long`           | `"9007199254740993"`   | `Int64StringConverter`   |

**`long` is a string on the wire, globally.** Past 2^53 a JSON number silently
loses precision in every JavaScript peer, and which ids grow that large is not
knowable when the contract is written. Reading still accepts a JSON number, so a
peer that has not adopted the contract degrades rather than fails.

## Wire formats — the non-JSON call sites

Config values, CLI arguments, and headers get the same forms through `Wire`,
which returns a `Result` instead of throwing.

```csharp
var zone = Wire.ParseTimeZone(options.Timezone);          // Result<TimeZoneInfo, WireFormatError>
var cutoff = Wire.ParseTime(row["cutoff"]);               // Result<TimeOnly, WireFormatError>
var wire = Wire.Format(TimeSpan.FromMinutes(90));         // "PT1H30M"
```

Rules that catch people out:

- **Instants always serialize as `Z`.** Parsing accepts a trailing offset and
  normalizes it, so `2026-07-26T06:30:00+08:00` round-trips out as
  `2026-07-25T22:30:00Z`. That is the contract, not a bug.
- **Times are whole seconds.** `Format(TimeOnly)` truncates; `ParseTime` rejects
  a fractional part outright.
- **Durations are time-based plus whole days.** `P1Y`, `P1M`, and `P1W` are
  rejected: a calendar month has no fixed length, so it cannot be a `TimeSpan`.
- **Timezones are IANA ids only.** `Singapore Standard Time` is rejected even on
  a host that could resolve it, and so is a bare `+08:00`.
- **Money is a decimal string, never a float.** Use `decimal`; do not reach for
  `double` and hope.

## Do not

- Do not hand-roll a format string. `ToString("yyyy-MM-dd")` scattered through a
  codebase is exactly the drift this package exists to end (the `zinc_date`
  DD-MM-YYYY bug class).
- Do not put a locale-formatted date on the wire. Display formatting is a
  frontend concern; the wire form is not negotiable.
- Do not call `.Get()` on a `Result` without checking first — use `Match`,
  `Then`, `Map`, or `GetOr`.
- Do not expect a deep-merge or an env-var→nested-path helper here. They are
  deliberately absent: `IConfiguration` provider layering IS the merge, and the
  configuration binder already owns `<Prefix>A__B` coercion. Porting them would
  re-implement the framework.

## Slugs and namespaced keys

```csharp
Slug.Slugify("  Crème Brûlée  ");                    // "creme-brulee"
Slug.NamespacedKey("AtomiCloud", "Express Parcel");  // Ok("atomicloud:express-parcel")
Slug.NamespacedKey("!!!", "key");                    // Err(KeyError)
```

`NamespacedKey` is total — a part that slugifies to empty comes back as an error,
never an exception. Feed it untrusted text freely.

The transform is NFKD fold → strip combining marks → lowercase → collapse runs of
non-alphanumerics to a single hyphen → trim hyphens. It is byte-parity with the
bun sibling; the pinned cases live in `fixtures/c0/wire-v1.json`. If you change
it, you have changed a cross-language contract.

## Key normalization

```csharp
KeyNormalizer.Canonical("error_portal");                  // "errorportal"
KeyNormalizer.KeysMatch("error-portal", "ErrorPortal");   // true
```

Separators (`_`, `-`, space, `.`) drop and case folds, so snake, kebab, camel,
and Pascal spellings of a key all match. This is what lets `error_portal:` in a
YAML file bind to an `ErrorPortal` options class.

## Telemetry attributes

`WireAttributes` bridges to the `ILoggerSink` / `IMetricsCollector` seams from
`AtomiCloud.Diene.Interfaces`, covering the kinds the seam library does not
declare and canonicalizing the keys:

```csharp
var attributes = WireAttributes.Normalize(new Dictionary<string, AttributeValue>
{
    ["shipped-on"] = WireAttributes.Date(receipt.ShippedOn),      // Text, "2026-07-25"
    ["declared_value"] = WireAttributes.Decimal(receipt.Amount),  // Text, exact — not Real
    ["confirmed_at"] = AttributeValue.Instant(receipt.ConfirmedAt),
}).Get();

sink.Emit(new LogRecord(receipt.ConfirmedAt, LogLevel.Info, "shipment confirmed", attributes));
```

`Normalize` reports a key that normalizes to empty, or two keys that collide once
normalized, rather than dropping one silently. Use it so `request_id` from one
service and `requestId` from another aggregate as one series.

## This package ships no TestHelper — and how to add one if that changes

There is no `AtomiCloud.Diene.CoreUtils.TestHelper`, on purpose. Every member
here is a deterministic value function: there is no port to fake, no clock to
inject, and the outputs are plain strings and BCL temporal types that stock
`Should().Be(...)` already asserts well. A helper would only re-export this
library's own round-trip tests. Consequently `pls test:meta` is a no-op in this
repository and no empty `meta` flag is uploaded to codecov.

Re-open the decision when — and only when — one of these becomes true:

- the API grows a seam a consumer must fake (an injectable clock, a source of
  ambient timezone data), or
- an assertion consumers repeat in every test appears (for example, "this
  payload is C0-conformant" as a single matcher rather than field-by-field
  equality).

To add one at that point:

1. Create `TestHelper/TestHelper.csproj` with `RootNamespace`, `AssemblyName`,
   and `PackageId` all set to `AtomiCloud.Diene.CoreUtils.TestHelper`, a
   `ProjectReference` to `../Lib/Lib.csproj`, and the same `LICENSE` / `README.md`
   / `logo.png` / `skills/**` pack includes the Lib project uses. The folder stays
   base-named `TestHelper`; only the published identity is per-instance.
2. Add one `<Project Path="TestHelper/TestHelper.csproj" />` line to
   `dotnet-base.slnx` and a `ProjectReference` from `UnitTest`.
3. Nothing else needs configuring: `.config/dotnet-base.test.yaml` already
   registers the meta ledger at `[*.TestHelper]*` @ 100, `scripts/local/dotnet-test.sh`
   activates the meta tier the moment a `TestHelper*.csproj` exists, and the
   `meta` CI job and codecov flag are already wired.
4. Write the meta suite: assert-the-asserter (every helper proven to FAIL on a
   known-bad case and pass on a known-good one), plus fixture invariants.
5. Add the second package id to `scripts/validate/dotnet-package.sh`
   (`package_ids`), raise its artifact count from two to four, and add the
   `dotnet add package` line back to `scripts/ci/pkg-validate.sh`.
6. Update this section and the README to cover the helper's usage.
