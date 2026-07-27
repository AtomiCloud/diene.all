---
name: diene-go-interfaces-usage
description: Use the Diene Go implementation-free interfaces library and its deterministic in-memory test helpers.
---

# Diene Go interfaces usage

Import `github.com/AtomiCloud/diene.go-interfaces/lib/interfaces` for portable
system, virtual filesystem, terminal, logging, and metrics seams. Depend on the
interfaces in application code; keep host-backed implementations in the owning
adapter library.

- Return ordinary `(T, error)` pairs. Every non-nil error must carry a
  `*problem.Error` from
  `github.com/AtomiCloud/diene.go-errors-problems/lib/problem`.
- Pass `context.Context` first to terminal, VFS, and delay operations.
- Treat a non-zero `TerminalOutput.ExitCode` as captured command output, not a
  launch error.
- Use `NewTerminalCommand`, `NewLogRecord`, and `NewMetricRecord` when caller
  maps or slices need independent ownership.

For consumer tests, import
`github.com/AtomiCloud/diene.go-interfaces/testhelper`. Its `InMemorySystem`,
`InMemoryVfs`, `InMemoryTerminal`, `InMemoryLoggerSink`, and
`InMemoryMetricsCollector` provide deterministic state, FIFO scripted results,
and read-only snapshots of recorded inputs. Script errors with the
`Enqueue…Result` methods. Plain injected errors are normalized into
`*problem.Error` values while preserving `errors.Is`; already problem-typed
errors are returned unchanged.
