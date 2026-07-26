// Package process binds the family's [interfaces.Terminal] seam to real
// operating-system processes.
//
// The interfaces sibling owns the seam and ships an in-memory implementation
// for tests; something has to ship the real one, and the harness is where it
// belongs because the harness is what actually runs built artifacts.
//
// It is the only place in this module that touches os/exec. Everything above it
// — the compiled-artifact driver, the journey runner, parity comparison — is
// written against the seam, which is why the harness can test itself without
// ever spawning a process.
package process
