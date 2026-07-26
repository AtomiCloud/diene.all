package schemaview_test

import (
	"reflect"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
)

func TestParsePointerAcceptsSupportedForms(t *testing.T) {
	t.Parallel()
	cases := map[string][]string{
		"#":               {},
		"#/$defs/body":    {"$defs", "body"},
		"#/$defs/a~1b":    {"$defs", "a/b"},
		"#/$defs/c~0d":    {"$defs", "c~d"},
		"#/$defs/a~1b~0c": {"$defs", "a/b~c"},
		"#/allOf/0":       {"allOf", "0"},
		"#/$defs/":        {"$defs", ""},
	}
	for reference, want := range cases {
		tokens, err := schemaview.ParsePointer(reference)
		if err != nil {
			t.Fatalf("%q must parse: %v", reference, err)
		}
		if !reflect.DeepEqual(tokens, want) {
			t.Fatalf("%q parsed to %v, want %v", reference, tokens, want)
		}
	}
}

func TestParsePointerRejectsUnsupportedForms(t *testing.T) {
	t.Parallel()
	for _, reference := range []string{
		"https://example.invalid/x.json",
		"other.json#/$defs/body",
		"#anchor",
		"#/%24defs/body",
		"#/$defs/bad~2escape",
		"#/$defs/dangling~",
		"",
		"/$defs/body",
	} {
		if _, err := schemaview.ParsePointer(reference); err == nil {
			t.Fatalf("%q must be rejected", reference)
		}
	}
}

func TestTokenEscapingRoundTrips(t *testing.T) {
	t.Parallel()
	for _, token := range []string{"body", "a/b", "c~d", "a/b~c", "", "~", "/"} {
		encoded := schemaview.EscapeToken(token)
		decoded, err := schemaview.UnescapeToken(encoded)
		if err != nil || decoded != token {
			t.Fatalf("token %q escaped to %q and decoded to %q (%v)", token, encoded, decoded, err)
		}
	}
}

func TestFormatPointerRendersTokens(t *testing.T) {
	t.Parallel()
	if got := schemaview.FormatPointer(nil); got != "#" {
		t.Fatalf("an empty token path renders as the root pointer, got %q", got)
	}
	if got := schemaview.FormatPointer([]string{"$defs", "a/b"}); got != "#/$defs/a~1b" {
		t.Fatalf("format escaped wrongly: %q", got)
	}
}

func TestChildDoesNotAliasItsParent(t *testing.T) {
	t.Parallel()
	parent := []string{"properties"}
	first := schemaview.Child(parent, "a")
	second := schemaview.Child(parent, "b")
	if first[1] != "a" || second[1] != "b" || len(parent) != 1 {
		t.Fatalf("child paths aliased their parent: %v %v %v", parent, first, second)
	}
}

func TestEqualTokens(t *testing.T) {
	t.Parallel()
	if !schemaview.EqualTokens(nil, []string{}) {
		t.Fatal("an empty path equals an empty path")
	}
	if !schemaview.EqualTokens([]string{"a", "b"}, []string{"a", "b"}) {
		t.Fatal("identical paths must compare equal")
	}
	if schemaview.EqualTokens([]string{"a"}, []string{"a", "b"}) {
		t.Fatal("paths of different length differ")
	}
	if schemaview.EqualTokens([]string{"a", "b"}, []string{"a", "c"}) {
		t.Fatal("paths with a different token differ")
	}
}

func TestCanonicalizePointerTokensRewritesOnlyNamePositions(t *testing.T) {
	t.Parallel()
	got := schemaview.CanonicalizePointerTokens([]string{"$defs", "Body_Name", "properties", "cache_region", "items"})
	want := []string{"$defs", "Body_Name", "properties", "cacheregion", "items"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("rewrote %v, want %v", got, want)
	}
	if got := schemaview.CanonicalizePointerTokens([]string{"dependentSchemas", "Cache-Region"}); got[1] != "cacheregion" {
		t.Fatalf("a dependentSchemas token must be canonicalized: %v", got)
	}
	if got := schemaview.CanonicalizePointerTokens(nil); len(got) != 0 {
		t.Fatalf("an empty path rewrites to an empty path: %v", got)
	}
}
