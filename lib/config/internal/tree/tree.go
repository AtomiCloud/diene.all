// Package tree resolves dotted configuration keys against a merged map using
// the family's canonical, casing-insensitive key matching. It descends through
// any string-keyed map — map[string]any and typed containers such as
// map[string]string alike — so the typed-container ownership contract and dotted
// lookup agree. It is an internal package: its API is exported so it can be
// black-box tested, but it is not part of the public config surface.
package tree

import (
	"reflect"
	"strings"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Lookup walks a dotted key against root, matching each segment across snake,
// kebab, camel, and Pascal spellings. It descends through any string-keyed map,
// so a nested typed container (for example map[string]string) resolves exactly
// like a nested map[string]any. It returns the resolved value and whether every
// segment was found.
func Lookup(root map[string]any, key string) (any, bool) {
	var current any = root
	for segment := range strings.SplitSeq(key, ".") {
		node := reflect.ValueOf(current)
		if !node.IsValid() || node.Kind() != reflect.Map || node.Type().Key().Kind() != reflect.String {
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

// MatchKey resolves segment against a string-keyed map value by canonical
// (separator- and case-insensitive) matching. It counts every sibling whose
// canonical form matches BEFORE resolving, so when more than one sibling
// collides the match is ambiguous and reported as not found even if one of them
// spells segment exactly. Resolution therefore never depends on Go map iteration
// order. node must be a reflect.Value of a map with string keys.
func MatchKey(node reflect.Value, segment string) (any, bool) {
	canonical := coreutils.CanonicalConfigKey(segment)
	var matched reflect.Value
	matches := 0
	iterator := node.MapRange()
	for iterator.Next() {
		if coreutils.CanonicalConfigKey(iterator.Key().String()) == canonical {
			matched = iterator.Value()
			matches++
		}
	}
	if matches == 1 {
		return matched.Interface(), true
	}
	return nil, false
}
