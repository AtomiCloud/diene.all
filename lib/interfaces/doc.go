// Package interfaces defines implementation-free seams for system, virtual
// filesystem, terminal, logging, and metrics work.
//
// Implementations return ordinary Go errors. Implementations in the Diene
// family use problem-typed errors from diene.go-errors-problems for expected
// failures, allowing callers to inspect structured details without a Result or
// Option wrapper.
package interfaces
