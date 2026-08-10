# Shared seams

`AtomiCloud.Diene.Interfaces` is the .NET member of the S33 cross-family
common-interfaces library. It DECLARES seams and ships mocks; it contains no
concrete host implementation.

## Seams owned here

| Seam                | Boundary                                             |
| ------------------- | ---------------------------------------------------- |
| `ISystem`           | process environment, working directory, clock, delay |
| `IVfs`              | virtual filesystem reads, writes, listing, deletion  |
| `ITerminal`         | child-process execution and captured output          |
| `ILoggerSink`       | structured log emission                              |
| `IMetricsCollector` | metric sample emission                               |

Traces are deliberately absent: the review ledger records them as
language-local with no cross-language shape parity, so the trace seam and its
mock belong to `AtomiCloud.Diene.Otel`. Otel IMPLEMENTS `ILoggerSink` and
`IMetricsCollector`; it never owns them.

## Never throws, never captures

Every fallible method returns `Result<T, SeamError>` from the published
`AtomiCloud.Diene.Result` package. A missing file, a refused sink, and a
cancelled delay are all failure VALUES carrying one stable id from
`SeamErrors`. Two exceptions are deliberate and are precondition violations
rather than seam outcomes, in the same class as `ArgumentNullException`:
constructing a value type with a null or blank required argument, and asking
`SeamWire.Name` for a value outside its enumeration.

A non-zero child exit code is a SUCCESSFUL `TerminalOutput`; only a launch
failure is a `SeamError`.

## Extraction boundary

No concrete filesystem or process helper moves into the shipped assembly. Host
adapters belong to the consumer that owns the runtime; `App/Adapters` holds
non-packable reference adapters purely so the integration tier can run the
shipped contract suites against a real host.

## Wire contract

`SeamWire` and `AttributeValue` carry the C0 serialization contract (R14):

- instants are RFC 3339 in UTC (`yyyy-MM-ddTHH:mm:ss.fffffffZ`);
- durations are ISO 8601 (`PT1M30S`);
- timezones are IANA ids resolved against the host database;
- every enumeration has one stable lowercase wire name, shared with the bun,
  dart, and go members of this family.

`AttributeValue` stores its payload in wire form, so a log or metric record that
round-trips through a transport is byte-identical to the record emitted. The
source-owned regression fixture is `fixtures/c0/seam-wire-v1.json`; it is
versioned and exercised in both the unit and integration tiers. Its explicit
`local-regression-only` status does not claim a shared cross-language fixture or
an external C0 proof.

## Contract parity

`SeamContracts` ships one behavioural suite per seam. The suites are
framework-agnostic and return a `ContractReport`, so the identical suite runs
against the in-memory mock in the meta tier and against a host-backed adapter in
the integration tier. Downstream implementors — `otel` first — prove conformance
with the same code instead of re-deriving expectations.
