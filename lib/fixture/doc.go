// Package fixture builds the layered configuration a harnessed service loads.
//
// A SIT run has to hand the system under test a REAL configuration document,
// not an in-memory map: a compiled artifact reads files and environment
// variables, so a fixture that only exists as a Go value proves nothing about
// the artifact's configuration contract. This package builds the R14 three-layer
// shape — full base defaults, a sparse landscape overlay, environment last —
// and materializes it onto a filesystem seam.
//
// # The environment layer is where the bugs live
//
// Environment encoding is the layer every family has re-implemented and
// re-broken, so this package emits exactly the C0 shape and nothing else:
// `__` for nesting, and INDEXED KEYS for collections — `FOO__0`, `FOO__1` —
// never JSON-in-env and never comma joining. [Bundle.Environ] is the single
// place that encoding exists.
//
// # Secrets stay blank
//
// A fixture never writes a secret into YAML. Blank in the document, injected
// through the environment layer (M4/M33): [Builder.WithSecret] enforces that
// pairing so a fixture cannot accidentally commit a credential into a base
// document a consumer copies.
//
// # Wire values
//
// Timestamps, durations, and timezone identifiers in a fixture cross the wire
// into the system under test, so they are produced by the core-utils sibling's
// C0 codecs ([Instant], [Duration], [Zone]) rather than by fmt — which is the
// bug class C0 §1 exists to kill.
package fixture
