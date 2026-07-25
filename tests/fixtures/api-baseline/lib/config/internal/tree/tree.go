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

// MatchKey resolves segment against node, preferring an exact hit and falling
// back to canonical (separator- and case-insensitive) matching.
func MatchKey(node map[string]any, segment string) (any, bool) {
	if value, ok := node[segment]; ok {
		return value, true
	}
	canonical := coreutils.CanonicalConfigKey(segment)
	for key, value := range node {
		if coreutils.CanonicalConfigKey(key) == canonical {
			return value, true
		}
	}
	return nil, false
}
