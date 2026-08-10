package testhelper

import (
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// TestingT is the minimal subset of *testing.T the assertions use. Any type
// with Helper and Fatalf satisfies it, which keeps the helpers decoupled from
// the concrete testing type and unit-testable in the meta tier.
type TestingT interface {
	Helper()
	Fatalf(format string, args ...any)
}

// RequireStarted fails t when a start helper returned an error or a nil handle,
// and returns the handle on success.
//
// It is generic over the four Started* types so one assertion covers every
// preset: a consumer writes RequireStarted(t, StartPostgres(ctx, opts)) and gets
// a non-nil handle or a stopped test.
func RequireStarted[S any](t TestingT, started *S, err error) *S {
	t.Helper()
	if err != nil {
		t.Fatalf("standardconfig testhelper: expected a started preset, got error: %v", err)
		return nil
	}
	if started == nil {
		t.Fatalf("%s", "standardconfig testhelper: expected a started preset, got nil with no error")
		return nil
	}
	return started
}

// RequireEntry fails t unless block declares a connection named key, and
// returns that entry on success.
func RequireEntry[E any](t TestingT, block map[string]E, key string) E {
	t.Helper()
	entry, found := block[key]
	if !found {
		var zero E
		t.Fatalf("standardconfig testhelper: no %q connection in the block; known keys: %v",
			key, standardconfig.Keys(block))
		return zero
	}
	return entry
}

// RequireUppercaseKeys fails t when any connection name in block breaks the
// UPPERCASE AUTHORING contract (R14).
//
// Assert it on a block as WRITTEN — one a start helper emitted, or one a test
// hand-built. A block that came out of the config loader has already lost its
// authored casing, so use [RequireConnectionNames] on that side instead.
func RequireUppercaseKeys[E any](t TestingT, block map[string]E) {
	t.Helper()
	for _, key := range standardconfig.Keys(block) {
		if !standardconfig.ValidKey(key) {
			t.Fatalf("standardconfig testhelper: connection name %q is not UPPERCASE (R14); pattern %s",
				key, standardconfig.UppercaseKeyPattern)
			return
		}
	}
}

// RequireConnectionNames fails t when any connection name in a DECODED block
// has no reachable environment override path.
//
// Schema validation cannot catch this — the config library matches keys
// canonically and rejects key-spelling constraints as authoring faults — so a
// consumer that wants the contract asserted in its own tests asserts it here.
func RequireConnectionNames[E any](t TestingT, block map[string]E) {
	t.Helper()
	for _, key := range standardconfig.Keys(block) {
		if !standardconfig.ValidConnectionName(key) {
			t.Fatalf("standardconfig testhelper: connection name %q is not an identifier, "+
				"so its environment override is unreachable; pattern %s",
				key, standardconfig.ConnectionNamePattern)
			return
		}
	}
}
