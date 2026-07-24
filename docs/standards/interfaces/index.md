# Interfaces

The interfaces package owns the TypeScript family's shared **effect-port contracts** — the
seams that let domain and service code stay independent of the process, filesystem, terminal,
and telemetry vendors underneath it. It ships types and framework-free test doubles; it ships
no concrete adapter.

This article builds on [Three-Layer Architecture](../three-layer-architecture/index.md),
[Functional practices](../functional-practices/index.md), and
[Stateless OOP and dependency injection](../stateless-oop-di/index.md). Ports are the
dependency-inverted boundary those standards describe; failures follow the Result-based
error-handling conventions; and adapters are constructor-injected against these contracts.

---

## What this package owns

`@atomicloud/diene.interfaces` owns exactly **five** ports and nothing else:

| Port                  | Concern                                           |
| --------------------- | ------------------------------------------------- |
| **System**            | process execution and the process environment     |
| **VirtualFileSystem** | file and directory access                         |
| **Terminal**          | terminal input and output (stdin, stdout, stderr) |
| **LoggerSink**        | structured, level-based log emission              |
| **MetricsCollector**  | counter, gauge, and histogram collection          |

Each port is a **dependency-light contract**: it names types and method shapes, carries no
vendor SDK dependency, and depends only on the published `@atomicloud/diene.result` type. The
package exposes these contracts from its root and its in-memory test doubles from the
`@atomicloud/diene.interfaces/test-helper` subpath.

The package deliberately does **not** own service configuration, wire or config semantics
(those belong to the separately owned C0 contracts standard), or any concrete adapter.

---

## Result-based failures

Every effect and every fallible port method returns the published
[`Result`](../functional-practices/index.md) value **directly**. Ports never throw and never
reject as normal control flow — a caller reasons about failure by inspecting the returned
`Result`, not by wrapping calls in `try`/`catch`.

- **Fallible operations** return a `Result` carrying a typed, port-specific error on the
  failure branch. Errors expose stable `port`, `code`, and `operation` fields so callers can
  `map`/`match` on them without parsing messages.
- **Telemetry emission is an effect and remains explicit.** Both `LoggerSink.emit` and
  `MetricsCollector.record`, as well as each sink's `flush`, return `Result<void, PortError>`.
  An adapter reports validation or transport failure through that Result; it never throws or
  silently converts a failed emission into success.
- A non-zero process exit from **System** is an ordinary result value, not an error. Reserve
  the error branch for the port failing to do its job (for example, a command that could not be
  spawned), not for the command reporting its own failure.

Because failures are values, a port and its in-memory double reach the **same** failure branch
for the same bad input. Consumers get one error model whether they run against a real adapter or
a mock.

---

## Validation and invariants

Contracts are only trustworthy if every implementation enforces the **same** invariants. The
package keeps those invariants in one place — shared, pure validation the ports and their test
doubles both call — so a mock can never silently accept input a real adapter would reject.

Invariants are expressed as the same Result the ports return: invalid input yields the failure
branch rather than a thrown exception. Representative rules the ports enforce:

- **System** — a command must be non-empty; a supplied timeout must be positive.
- **VirtualFileSystem** — a path must be non-empty; reading a missing entry, writing where a
  directory exists, or listing a file surfaces the matching typed error.
- **Terminal** — writing to or reading from a closed stream surfaces a closed-stream error.
- **MetricsCollector** — a metric has a portable kind, name, finite value, optional non-blank
  unit, and finite primitive attributes; counter values must not be negative.

The rule for anyone adding an implementation: **reuse the shared validation; never re-derive
it.** Parity between real and fake is a property of shared code, not of careful duplication.

---

## Adapters vs contracts vs OTel

Three layers, three owners — keep them separate:

- **Contracts (this package).** Types and invariants only. No vendor SDK, no I/O, no telemetry
  exporter. Domain and service code depend here and nowhere lower.
- **Adapters (elsewhere).** Concrete implementations of these contracts against a real vendor
  or runtime (a real filesystem, a real process spawner, a real metrics registry). They live in
  their own packages, are wired in by dependency injection, and never leak their vendor back
  through the contract type.
- **OTel (the separate OTel package).** **Tracing is not owned here.** Per RB-19, trace and
  span contracts, their in-memory doubles, and any vendor- or SDK-specific telemetry assertions
  are language-local to the OTel package. `LoggerSink` and `MetricsCollector` here are plain
  effect seams; trace-context propagation and span emission belong to OTel, which composes with
  these ports rather than replacing them.

If a contract would force a decision about a specific vendor, exporter, or wire format, it does
not belong in this package.

---

## Wiring

Consumers depend on the **contract**, receive a concrete implementation by injection, and stay
oblivious to which one they got:

- Import the port **types** from the package root.
- Accept a port as a constructor dependency; never construct a concrete adapter inside domain
  or service code.
- Branch on the returned `Result` at the boundary; propagate or `map` the typed error rather
  than throwing.
- Obtain trace-aware logging from the OTel package when you need it — it layers on top of these
  seams; it is not a second logging contract.

The published package installs `@atomicloud/diene.result` as a runtime dependency, so the
`Result` type resolves for both ESM and CommonJS consumers without extra setup.

---

## Test-helper use

Framework-free in-memory doubles and assertions ship at
`@atomicloud/diene.interfaces/test-helper`. They carry **no** dependency on any test framework,
so any runner can use them.

- **Mocks** implement the real contracts, record validated interactions deterministically
  (including operational failures), and enforce the same invariants as real adapters — they
  reject malformed input before it can mutate fake state.
- **Assertions** are plain functions that fail with a precise message and otherwise pass;
  they read the recorded interactions to check what a port was asked to do.
- **Parity and assert-the-asserter.** The package's own tests prove each shipped assertion both
  fails on a known-bad interaction and passes on a known-good one, and run a shared contract
  suite so a mock and any dependency-free reference implementation agree on the same inputs.

Interfaces owns the doubles for its five ports. **Trace and vendor/SDK-specific telemetry test
helpers live in the OTel package**, consistent with the boundary above. When you need a fake
`System`, `VirtualFileSystem`, `Terminal`, `LoggerSink`, or `MetricsCollector` in a consumer
test, import it from the test-helper subpath instead of hand-rolling one — the shipped double
already tracks the real contract.
