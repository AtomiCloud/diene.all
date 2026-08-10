package schemaview_test

import (
	"reflect"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
)

func TestAuthoredLocationRestoresSpellings(t *testing.T) {
	t.Parallel()
	original := map[string]any{
		"Demo-Block": map[string]any{
			"CacheRegion": "east",
			"List":        []any{map[string]any{"Item_Key": "x"}},
		},
	}
	cases := []struct {
		canonical []string
		want      []string
	}{
		{canonical: nil, want: []string{}},
		{canonical: []string{"demoblock"}, want: []string{"Demo-Block"}},
		{canonical: []string{"demoblock", "cacheregion"}, want: []string{"Demo-Block", "CacheRegion"}},
		{canonical: []string{"demoblock", "list", "0", "itemkey"}, want: []string{"Demo-Block", "List", "0", "Item_Key"}},
	}
	for _, testCase := range cases {
		got := schemaview.AuthoredLocation(original, testCase.canonical)
		if !reflect.DeepEqual(got, testCase.want) {
			t.Fatalf("AuthoredLocation(%v) = %v, want %v", testCase.canonical, got, testCase.want)
		}
	}
}

func TestAuthoredLocationKeepsDottedNamesAsOneSegment(t *testing.T) {
	t.Parallel()
	// A property name may itself contain a dot; the segment must survive intact,
	// which is exactly why the location stays structured until this point.
	original := map[string]any{"a.b": map[string]any{"c.d": "value"}}
	got := schemaview.AuthoredLocation(original, []string{"a.b", "c.d"})
	if !reflect.DeepEqual(got, []string{"a.b", "c.d"}) {
		t.Fatalf("a dotted name must stay one segment: %v", got)
	}
}

func TestAuthoredLocationTreatsAMapKeyNamedZeroAsAKey(t *testing.T) {
	t.Parallel()
	// The current value decides: inside a map "0" is a key, inside an array it is
	// an index.
	asKey := map[string]any{"0": map[string]any{"Inner_Key": "v"}}
	if got := schemaview.AuthoredLocation(asKey, []string{"0", "innerkey"}); !reflect.DeepEqual(got, []string{"0", "Inner_Key"}) {
		t.Fatalf("a map key named 0 must stay a key: %v", got)
	}
	asIndex := map[string]any{"list": []any{map[string]any{"Inner_Key": "v"}}}
	if got := schemaview.AuthoredLocation(asIndex, []string{"list", "0", "innerkey"}); !reflect.DeepEqual(got, []string{"list", "0", "Inner_Key"}) {
		t.Fatalf("an array index must stay an index: %v", got)
	}
}

func TestAuthoredLocationAppendsRemainderOnMismatch(t *testing.T) {
	t.Parallel()
	original := map[string]any{"known": []any{"scalar"}}
	cases := []struct {
		name      string
		canonical []string
		want      []string
	}{
		{name: "missing key", canonical: []string{"missing", "deeper"}, want: []string{"missing", "deeper"}},
		{name: "index out of range", canonical: []string{"known", "9"}, want: []string{"known", "9"}},
		{name: "index not a number", canonical: []string{"known", "notanindex"}, want: []string{"known", "notanindex"}},
		{name: "descend through a scalar", canonical: []string{"known", "0", "deeper"}, want: []string{"known", "0", "deeper"}},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			if got := schemaview.AuthoredLocation(original, testCase.canonical); !reflect.DeepEqual(got, testCase.want) {
				t.Fatalf("%s = %v, want %v", testCase.name, got, testCase.want)
			}
		})
	}
	if got := schemaview.AuthoredLocation("scalar-root", []string{"a"}); !reflect.DeepEqual(got, []string{"a"}) {
		t.Fatalf("a scalar root appends the remainder: %v", got)
	}
}

func TestUniqueCanonicalKey(t *testing.T) {
	t.Parallel()
	node := map[string]any{"Cache-Region": "east", "other": 1}
	name, value, found := schemaview.UniqueCanonicalKey(node, "cacheregion")
	if !found || name != "Cache-Region" || value != "east" {
		t.Fatalf("lookup = %q %v %v", name, value, found)
	}
	if _, _, found = schemaview.UniqueCanonicalKey(node, "missing"); found {
		t.Fatal("an absent canonical form must not resolve")
	}
}
