package resource_test

import (
	"encoding/json"
	"net/url"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/resource"
)

func TestBlockIDIsAValidAbsoluteURIForAwkwardKeys(t *testing.T) {
	t.Parallel()
	keys := []string{
		"demo", "a/b", "..", "../../etc/passwd", "ünïcode", "with space",
		"$weird", "", "a?b#c", "tab\tkey", `quote"key`,
	}
	seen := map[string]string{}
	for _, key := range keys {
		identity := resource.BlockID(key)
		parsed, err := url.Parse(identity)
		if err != nil || !parsed.IsAbs() || parsed.Fragment != "" {
			t.Fatalf("key %q produced an unusable identity %q (%v)", key, identity, err)
		}
		if identity != parsed.String() {
			t.Fatalf("key %q produced an identity that does not round-trip: %q vs %q", key, identity, parsed.String())
		}
		if other, taken := seen[identity]; taken {
			t.Fatalf("keys %q and %q collide on %q", other, key, identity)
		}
		seen[identity] = key
	}
}

func TestBlockIDCarriesThePrefixAndSuffix(t *testing.T) {
	t.Parallel()
	identity := resource.BlockID("demo")
	if !strings.HasPrefix(identity, resource.Prefix) || !strings.HasSuffix(identity, resource.Suffix) {
		t.Fatalf("identity %q must carry the fixed prefix and suffix", identity)
	}
	encoded := strings.TrimSuffix(strings.TrimPrefix(identity, resource.Prefix), resource.Suffix)
	if strings.ContainsAny(encoded, "/+=") {
		t.Fatalf("the encoded segment must stay URL-safe and unpadded: %q", encoded)
	}
}

func TestBlockIDIsStableAcrossCalls(t *testing.T) {
	t.Parallel()
	first := resource.BlockID("a/b")
	for range 16 {
		if resource.BlockID("a/b") != first {
			t.Fatal("the identity of one key must never vary")
		}
	}
}

func TestNormalizeJSONStringMatchesEncodingJSON(t *testing.T) {
	t.Parallel()
	cases := []string{
		"demo", "ünïcode", "", "a/b",
		"\xff", "valid\xffinvalid", "\xed\xa0\x80", "two\xff\xfebytes",
	}
	for _, text := range cases {
		encoded, err := json.Marshal(text)
		if err != nil {
			t.Fatalf("marshal %q: %v", text, err)
		}
		var decoded string
		if err = json.Unmarshal(encoded, &decoded); err != nil {
			t.Fatalf("unmarshal %q: %v", text, err)
		}
		if got := resource.NormalizeJSONString(text); got != decoded {
			t.Fatalf("normalize(%q) = %q, encoding/json round trip = %q", text, got, decoded)
		}
	}
}

func TestBlockIDAgreesWithTheJSONVisibleKey(t *testing.T) {
	t.Parallel()
	// A key with invalid UTF-8 can only ever appear in an artifact as its
	// normalized spelling, so both must derive the same identity.
	raw := "bad\xffkey"
	if resource.BlockID(raw) != resource.BlockID(resource.NormalizeJSONString(raw)) {
		t.Fatal("compose-time and artifact-time identities must agree")
	}
}
