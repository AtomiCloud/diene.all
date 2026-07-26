// Package testhelper is the Go family's TestHelper bundle.
//
// Every other library in the family that ships a TestHelper ships it as its own
// `testhelper` sub-package, which leaves a consumer's SIT suite importing seven
// of them by hand and, worse, guessing which one owns a given fake. This package
// is the one import that answers that: it re-exports the sibling helpers under
// sibling-qualified names, so `ProblemAssertError`, `AuthNewFakeIDP`, and
// `PresetStartPostgres` say where they come from without a single import alias.
//
// It bundles the seven helpers that EXIST. The core-utils sibling deliberately
// ships none — pure deterministic functions have no seam to fake — so there is
// nothing to re-export and no empty facade pretending otherwise.
//
// The sibling packages remain importable directly. A consumer that wants the
// full surface of one helper should import it; this bundle carries the fakes,
// constructors, and assertion entry points a SIT suite reaches for, not a
// mirror of every symbol.
//
// # Its own glue
//
// On top of the bundle it ships what only the harness can:
//
//   - [StartStack] — Testcontainers glue that boots the four frozen infra
//     presets together and emits the configuration blocks that address them.
//     This is the DB-adapter integration tier (G1); telemetry infrastructure is
//     never spun up, there is no fake OTLP collector, and real export is proven
//     at SIT against the Garden preview environment instead.
//   - [NewScriptedDriver] and [EchoEntrypoint] — drivers that let a consumer
//     test its own journeys without a system under test.
//   - [AssertStep], [AssertReport], and friends — the assertions a harness
//     consumer would otherwise rewrite in every suite.
//
// Everything here is proven by the meta tier, including the assertions
// themselves: each one is shown to pass on known-good input and fail on
// known-bad, because an assertion helper that cannot fail is worse than none.
package testhelper
