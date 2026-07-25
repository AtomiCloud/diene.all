package tree_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/tree"
)

func TestLookupResolvesNestedDottedKey(t *testing.T) {
	t.Parallel()
	root := map[string]any{"app": map[string]any{"landscape": "lapras"}}
	value, ok := tree.Lookup(root, "app.landscape")
	if !ok || value != "lapras" {
		t.Fatalf("lookup = %v %v", value, ok)
	}
}

func TestLookupMatchesAcrossCasings(t *testing.T) {
	t.Parallel()
	root := map[string]any{"App": map[string]any{"Land-Scape": "lapras"}}
	value, ok := tree.Lookup(root, "app.landscape")
	if !ok || value != "lapras" {
		t.Fatalf("casing-insensitive lookup = %v %v", value, ok)
	}
}

func TestLookupMissingKey(t *testing.T) {
	t.Parallel()
	if _, ok := tree.Lookup(map[string]any{}, "nope"); ok {
		t.Fatal("missing key must not resolve")
	}
}

func TestLookupThroughScalarMidPath(t *testing.T) {
	t.Parallel()
	if _, ok := tree.Lookup(map[string]any{"app": "scalar"}, "app.landscape"); ok {
		t.Fatal("descending through a scalar must not resolve")
	}
}

func TestMatchKeyExactAndCanonical(t *testing.T) {
	t.Parallel()
	node := map[string]any{"my-key": 1}
	if value, ok := tree.MatchKey(node, "my-key"); !ok || value != 1 {
		t.Fatalf("exact match = %v %v", value, ok)
	}
	if value, ok := tree.MatchKey(node, "myKey"); !ok || value != 1 {
		t.Fatalf("canonical match = %v %v", value, ok)
	}
	if _, ok := tree.MatchKey(node, "other"); ok {
		t.Fatal("unrelated key must not match")
	}
}

func TestMatchKeyAmbiguousIsNotFound(t *testing.T) {
	t.Parallel()
	// Two siblings share the canonical form; the match is ambiguous and must be
	// reported as not found rather than resolved by map iteration order — even
	// when the looked-up segment spells one sibling exactly.
	node := map[string]any{"data-dir": 1, "dataDir": 2}
	if _, ok := tree.MatchKey(node, "datadir"); ok {
		t.Fatal("a non-exact ambiguous canonical match must be not found")
	}
	if _, ok := tree.MatchKey(node, "dataDir"); ok {
		t.Fatal("an exact hit must still be rejected when a canonical alias sibling exists")
	}
}
