// Package interfaces defines implementation-free seams for system, virtual
// filesystem, terminal, logging, and metrics work.
//
// Every non-nil error returned through these seams must carry a *problem.Error
// from diene.go-errors-problems, allowing callers to recover structured
// details with errors.As while preserving cause matching with errors.Is.
package interfaces
