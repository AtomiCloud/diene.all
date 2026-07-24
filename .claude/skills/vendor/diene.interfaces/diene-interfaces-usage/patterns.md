# @atomicloud/diene.interfaces — patterns

## Do

- Import the port **types** from the package root
  (`@atomicloud/diene.interfaces`); let the exports map pick the right module and
  declaration file for your module system.
- Depend on the **contract**, not a concrete implementation. Accept a port
  (System, VirtualFileSystem, Terminal, LoggerSink, or MetricsCollector) as a
  constructor dependency and let the caller inject the adapter.
- Branch on the returned `Result`. Fallible methods return the published
  `@atomicloud/diene.result` value directly; `map`/`match` the typed error at the
  boundary and propagate it rather than throwing.
- Treat a non-zero process exit from **System** as an ordinary result value — the
  error branch is for the port failing to do its job, not for a command reporting
  its own failure.
- Get trace-aware logging from the **OTel package** when you need it. It layers on
  top of these seams; it is not a second logging contract.

## Don't

- Don't deep-import into `dist/` internals; only the root entry and the
  `test-helper` subpath are public.
- Don't rely on side effects at import time — the package is `sideEffects: false`.
- Don't re-derive a port's invariants in your own adapter. Reuse the package's
  shared validation so your adapter rejects exactly what the mock rejects.
- Don't look for tracing or span contracts here — they live in the OTel package
  (RB-19).
- Don't wrap port calls in `try`/`catch` for normal control flow; ports do not
  throw.

## Test doubles

In-memory mocks and assertions ship on the subpath
`@atomicloud/diene.interfaces/test-helper` and carry **no** test-framework
dependency, so any runner can use them.

- Import a fake System, VirtualFileSystem, Terminal, LoggerSink, or
  MetricsCollector from the subpath instead of hand-rolling one — the shipped
  double already tracks the real contract, records interactions deterministically,
  and enforces the same invariants (it rejects what a real port rejects).
- Use the shipped assertions to check what a port was asked to do; they fail with
  a precise message and otherwise pass.
- Trace and vendor/SDK-specific telemetry doubles are **not** here — the OTel
  TestHelper owns those.

The concrete contract names are `System`, `VirtualFileSystem`, `Terminal`,
`LoggerSink`, and `MetricsCollector`. Their matching doubles are prefixed with
`InMemory` and live only on `/test-helper`; root remains the production entry.
