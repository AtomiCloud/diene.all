// Package tree resolves dotted configuration keys against a merged map using
// the family's canonical, casing-insensitive key matching. It is an internal
// package: its API is exported so it can be black-box tested, but it is not part
// of the public config surface.
package tree

import (
	"strings"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Lookup walks a dotted key against root, matching each segment across snake,
// kebab, camel, and Pascal spellings. It returns the resolved value and whether
// every segment was found.
func Lookup(root map[string]any, key string) (any, bool) {
	var current any = root
	for segment := range strings.SplitSeq(key, ".") {
		node, ok := current.(map[string]any)
		if !ok {
			return nil, false
		}
		value, found := MatchKey(node, segment)
		if !found {
			return nil, false
		}
		current = value
	}
	return current, true
}

// MatchKey resolves segment against node by canonical (separator- and
// case-insensitive) matching. It counts every sibling whose canonical form
// matches BEFORE resolving, so when more than one sibling collides the match is
// ambiguous and reported as not found even if one of them spells segment
// exactly. Resolution therefore never depends on Go map iteration order.
func MatchKey(node map[string]any, segment string) (any, bool) {
	canonical := coreutils.CanonicalConfigKey(segment)
	var matched any
	matches := 0
	for key, value := range node {
		if coreutils.CanonicalConfigKey(key) == canonical {
			matched = value
			matches++
		}
	}
	if matches == 1 {
		return matched, true
	}
	return nil, false
}
