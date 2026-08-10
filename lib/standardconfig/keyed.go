package standardconfig

import (
	"regexp"
	"slices"
	"strings"
)

// UppercaseKeyPattern is the AUTHORING contract for a connection name: an
// UPPERCASE letter followed by UPPERCASE letters, digits, and underscores
// (R14, C0 §3).
//
// Every preset is a keyed map of named connections — MAIN, REPLICA, SESSION —
// so a second instance is a YAML entry rather than a schema change, and the
// names are UPPERCASE so a connection reads as a constant at every call site.
//
// It applies to how a name is WRITTEN, in YAML and in the environment override
// path. It does not survive loading: the config library canonicalizes key
// spelling, so a name authored as MAIN reaches a decoded block as main. Use
// [ValidKey] on authored names; use [ValidConnectionName] on decoded ones.
const UppercaseKeyPattern = `^[A-Z][A-Z0-9_]*$`

// ConnectionNamePattern is the contract a connection name must satisfy in a
// DECODED block: a letter followed by letters, digits, and underscores, in any
// case.
//
// This is the half of the R14 contract that survives loading, and it is the
// half with teeth. A connection is overridden through the environment as
// <PREFIX>CACHE__<NAME>__PASSWORD, so a name carrying a hyphen, a dot, or a
// space has no reachable environment path at all — its secret can never be
// injected, and the failure surfaces in a landscape rather than in a test.
const ConnectionNamePattern = `^[A-Za-z][A-Za-z0-9_]*$`

// uppercaseKey and connectionName are the compiled patterns. They are compiled
// once because validation runs over every connection of every preset at
// startup.
var (
	uppercaseKey   = regexp.MustCompile(UppercaseKeyPattern)
	connectionName = regexp.MustCompile(ConnectionNamePattern)
)

// ValidKey reports whether name satisfies the UPPERCASE AUTHORING contract
// (R14).
//
// Check it against names as WRITTEN — a YAML key, a testhelper's emitted block,
// a constant in code. Checking it against a block that came out of the config
// loader always fails, because the loader canonicalizes key spelling on the way
// through; [ValidConnectionName] is the check for that side of the boundary.
func ValidKey(name string) bool {
	return uppercaseKey.MatchString(name)
}

// ValidConnectionName reports whether name is usable as a connection name in a
// decoded block: an identifier, so it has a reachable environment override
// path.
func ValidConnectionName(name string) bool {
	return connectionName.MatchString(name)
}

// Keys returns the connection names declared in block, in stable (sorted)
// order.
//
// Go map iteration is randomized, so anything that enumerates connections — a
// validation report, a log line, a health check — sorts here rather than each
// growing its own ordering.
func Keys[E any](block map[string]E) []string {
	names := make([]string, 0, len(block))
	for name := range block {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// Named resolves one connection out of a preset block, matching the name
// case-insensitively.
//
// Case-insensitive is not a convenience here, it is the only thing that works.
// Connection names are AUTHORED in UPPERCASE (R14) and code asks for
// Named(block, "MAIN"), but the config library canonicalizes key spelling, so
// the decoded block is keyed by main. A lookup that insisted on the authored
// casing would resolve nothing a service ever actually loaded.
//
// An exact match always wins. When only case-insensitive matches exist and
// there is more than one, the result is a problem rather than a coin flip —
// the config library rejects canonically colliding siblings in a loaded
// document, so this can only be reached from a hand-built block, and silently
// picking one of two would hide the mistake.
//
// A missing connection is a problem-typed error naming the connections that ARE
// declared, not a zero value: a typo should fail where it is used rather than
// surface later as a dial to host "".
func Named[E any](problems *Problems, block map[string]E, name string) (E, error) {
	var zero E
	if entry, found := block[name]; found {
		return entry, nil
	}
	matches := make([]string, 0, 1)
	for _, declared := range Keys(block) {
		if strings.EqualFold(declared, name) {
			matches = append(matches, declared)
		}
	}
	if problems == nil {
		if len(matches) == 1 {
			return block[matches[0]], nil
		}
		return zero, errUnconfigured()
	}
	switch len(matches) {
	case 1:
		return block[matches[0]], nil
	case 0:
		return zero, problems.Raise(ProblemConnectionUnknown,
			"no connection is configured under this name",
			map[string]any{"name": name, "known": Keys(block)})
	default:
		return zero, problems.Raise(ProblemConnectionAmbiguous,
			"more than one connection name differs from this one only by case",
			map[string]any{"name": name, "matches": matches})
	}
}

// ValidateKeys rejects a preset block whose connection names have no reachable
// environment override path.
//
// A service calls it once per block at startup, right after decoding, so a
// connection named rate-limit fails next to the schema validation instead of
// silently never receiving its secret in production.
//
// It deliberately does NOT assert UPPERCASE. By the time a block is decoded the
// authored casing is gone, so an UPPERCASE assertion here would reject every
// document the loader ever produced. Assert the authoring half with [ValidKey]
// against the names you wrote, not the names you loaded.
func ValidateKeys[E any](problems *Problems, blockKey string, block map[string]E) error {
	if problems == nil {
		return errUnconfigured()
	}
	invalid := make([]string, 0, len(block))
	for _, name := range Keys(block) {
		if !ValidConnectionName(name) {
			invalid = append(invalid, name)
		}
	}
	if len(invalid) == 0 {
		return nil
	}
	return problems.Raise(ProblemConnectionKeyInvalid,
		"connection names must be identifiers so their environment overrides are reachable: "+
			strings.Join(invalid, ", "),
		map[string]any{"block": blockKey, "invalid": invalid, "pattern": ConnectionNamePattern})
}

// errUnconfigured reports the one failure this library cannot describe as a
// problem: being handed no problem factory to describe failures with.
//
// It is deliberately a plain error. Minting an RFC 9457 envelope needs a
// portal, and a nil [Problems] is exactly the absence of one, so pretending
// otherwise would attribute the fault to a portal that was never supplied.
func errUnconfigured() error {
	return errNoProblems{}
}

// errNoProblems is the plain error value [errUnconfigured] returns. It is a
// distinct type so a consumer can match it with errors.As while it stays
// comparable for errors.Is.
type errNoProblems struct{}

// Error describes the missing problem factory and how to supply one.
func (errNoProblems) Error() string {
	return "standardconfig: no problem factory supplied; construct one with NewProblems(portal)"
}
