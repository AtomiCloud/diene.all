// Package schemaview turns an authored draft-2020-12 configuration schema into
// the form the validator actually evaluates, so that one equivalence relation
// governs both sides of validation.
//
// The family treats configuration keys as equal when their canonical forms match
// (separator- and case-insensitively), which is exactly how Config.Decode
// resolves a dotted key. Aliasing an instance onto a schema's authored spellings
// cannot express that relation: a negated branch has no "accepted spelling" at
// all, and names that appear only in "required" or as a "dependentRequired"
// trigger are never reachable that way. Instead this package canonicalizes BOTH
// sides once — every name position in the schema, every object key in the
// instance — and hands the canonical pair to the unmodified compiler. Every key
// comparison the compiler makes is then a comparison of canonical forms, so two
// spellings Decode treats as one key always validate identically, for every
// keyword, with no shadow evaluator.
//
// Canonicalization is exact only over a fixed subset of the dialect, so the
// audit rejects the constructs that would otherwise be silently mis-evaluated —
// key-spelling constraints and reference forms outside the supported local
// pointer grammar. Rejections are authoring faults, reported as plain errors.
//
// It is an internal package with an exported, black-box-testable API, not part
// of the public config surface.
package schemaview

import (
	"encoding/json"
	"errors"
	"slices"
	"strconv"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Normalize re-encodes an authored schema into the generic JSON value tree
// (map[string]any, []any, float64, string, bool, nil) the compiler consumes. An
// author may legally build a fragment from typed Go containers, so every later
// walk works from this form rather than guessing at container types. A cyclic or
// unencodable schema fails fast here, because json.Marshal rejects it.
func Normalize(schema map[string]any) (map[string]any, error) {
	raw, marshalErr := json.Marshal(schema)
	normalized := map[string]any{}
	decodeErr := json.Unmarshal(raw, &normalized)
	if joined := errors.Join(marshalErr, decodeErr); joined != nil {
		return nil, joined
	}
	return normalized, nil
}

// CanonicalKey returns the canonical form of a configuration key: the same rule
// Config.Decode matches with, so schema and instance share one relation.
func CanonicalKey(key string) string { return coreutils.CanonicalConfigKey(key) }

// SortedNames returns the keys of a map in sorted order, so every traversal,
// report, and rewrite is deterministic.
func SortedNames(declared map[string]any) []string {
	names := make([]string, 0, len(declared))
	for name := range declared {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// Index renders an array position as a pointer token.
func Index(position int) string { return strconv.Itoa(position) }

// ParseIndex reads an array position from a pointer token, rejecting anything
// that is not a plain non-negative decimal.
func ParseIndex(token string) (int, error) {
	position, err := strconv.Atoi(token)
	if err != nil {
		return 0, err
	}
	if position < 0 {
		return 0, errors.New("negative array index")
	}
	return position, nil
}
