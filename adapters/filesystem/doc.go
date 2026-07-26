// Package filesystem binds the family's [interfaces.Vfs] seam to the real
// operating-system filesystem.
//
// The interfaces sibling owns the seam and ships an in-memory implementation for
// tests, and no library in the family ships a host one — so the harness does,
// for the same reason it ships the terminal binding: a fixture materialized only
// into memory is a fixture a compiled artifact cannot read, which would make the
// compiled-artifact driver useless.
//
// It is the only place in this module that touches os and path/filepath.
package filesystem
