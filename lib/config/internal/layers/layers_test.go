package layers_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/layers"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

func TestNewViperParsesYAML(t *testing.T) {
	t.Parallel()
	if layers.NewViper() == nil {
		t.Fatal("NewViper returned nil")
	}
}

func TestBaseViperReadsSettings(t *testing.T) {
	t.Parallel()
	base, err := layers.BaseViper([]byte("app:\n  landscape: lapras\n"))
	if err != nil {
		t.Fatalf("base viper: %v", err)
	}
	if base.GetString("app.landscape") != "lapras" {
		t.Fatalf("parsed settings wrong: %v", base.AllSettings())
	}
}

func TestBaseViperEmptyDocument(t *testing.T) {
	t.Parallel()
	base, err := layers.BaseViper(nil)
	if err != nil || len(base.AllSettings()) != 0 {
		t.Fatalf("empty document must yield an empty viper: %v %v", base.AllSettings(), err)
	}
}

func TestBaseViperMalformedDocument(t *testing.T) {
	t.Parallel()
	if _, err := layers.BaseViper([]byte("\t not: [valid")); err == nil {
		t.Fatal("malformed YAML must error")
	}
}

func TestMergeOverlayCollapsesCrossSpelling(t *testing.T) {
	t.Parallel()
	base, err := layers.BaseViper([]byte("demo:\n  dataDir: base-value\n"))
	if err != nil {
		t.Fatalf("base: %v", err)
	}
	if err := layers.MergeOverlay(base, []byte("demo:\n  data-dir: overlay-value\n")); err != nil {
		t.Fatalf("merge: %v", err)
	}
	demo, ok := base.AllSettings()["demo"].(map[string]any)
	if !ok {
		t.Fatalf("demo missing: %v", base.AllSettings())
	}
	matches := 0
	for key, value := range demo {
		if coreutils.CanonicalConfigKey(key) == "datadir" {
			matches++
			if value != "overlay-value" {
				t.Fatalf("overlay must win: %v = %v", key, value)
			}
		}
	}
	if matches != 1 {
		t.Fatalf("cross-spelled keys must collapse to one, found %d in %v", matches, demo)
	}
}

func TestMergeOverlayMalformed(t *testing.T) {
	t.Parallel()
	base, err := layers.BaseViper([]byte("demo:\n  region: local\n"))
	if err != nil {
		t.Fatalf("base: %v", err)
	}
	if err := layers.MergeOverlay(base, []byte("\t not: [valid")); err == nil {
		t.Fatal("malformed overlay must error")
	}
}

func TestAlignKeysRewritesToBaseSpelling(t *testing.T) {
	t.Parallel()
	base := map[string]any{
		"cacheregion": "b",
		"nested":      map[string]any{"mykey": "b"},
		"scalar":      "b",
	}
	overlay := map[string]any{
		"cache-region": "o",
		"nested":       map[string]any{"my-key": "o"},
		"scalar":       map[string]any{"unexpected": true},
		"fresh":        1,
	}
	aligned := layers.AlignKeys(base, overlay)
	if aligned["cacheregion"] != "o" {
		t.Fatalf("cross-spelled key not aligned: %v", aligned)
	}
	nested, ok := aligned["nested"].(map[string]any)
	if !ok || nested["mykey"] != "o" {
		t.Fatalf("nested key not aligned: %v", aligned["nested"])
	}
	// A key that matches by name but whose shapes differ (map vs scalar) keeps the
	// overlay value under the base spelling.
	if _, ok := aligned["scalar"].(map[string]any); !ok {
		t.Fatalf("mismatched-shape value not preserved: %v", aligned["scalar"])
	}
	if aligned["fresh"] != 1 {
		t.Fatalf("fresh overlay key must be kept: %v", aligned["fresh"])
	}
}

func TestResolveLandscapeExplicitWins(t *testing.T) {
	t.Parallel()
	base := map[string]any{"app": map[string]any{"landscape": "base-value"}}
	if got := layers.ResolveLandscape(base, "explicit"); got != "explicit" {
		t.Fatalf("explicit landscape must win: %q", got)
	}
}

func TestResolveLandscapeFromBase(t *testing.T) {
	t.Parallel()
	base := map[string]any{"app": map[string]any{"landscape": "pichu"}}
	if got := layers.ResolveLandscape(base, ""); got != "pichu" {
		t.Fatalf("base landscape = %q", got)
	}
}

func TestResolveLandscapeMissing(t *testing.T) {
	t.Parallel()
	if got := layers.ResolveLandscape(map[string]any{}, ""); got != "" {
		t.Fatalf("missing landscape must be empty: %q", got)
	}
}

func TestResolveLandscapeNonString(t *testing.T) {
	t.Parallel()
	base := map[string]any{"app": map[string]any{"landscape": 7}}
	if got := layers.ResolveLandscape(base, ""); got != "" {
		t.Fatalf("non-string landscape must be empty: %q", got)
	}
}

func TestValidateLandscapeAcceptsTokens(t *testing.T) {
	t.Parallel()
	for _, token := range []string{"lapras", "pichu-1", "prod_eu", "AZ09"} {
		if err := layers.ValidateLandscape(token); err != nil {
			t.Fatalf("%q must be valid: %v", token, err)
		}
	}
}

func TestValidateLandscapeRejectsSeparatorsAndDots(t *testing.T) {
	t.Parallel()
	for _, token := range []string{"", "../secret", "a/b", "a.b", "..", "a b", "a:b", "a\\b"} {
		if err := layers.ValidateLandscape(token); err == nil {
			t.Fatalf("%q must be rejected", token)
		}
	}
}

func TestOverlayPathResolvesInsideDir(t *testing.T) {
	t.Parallel()
	dir := "/etc/config"
	path, err := layers.OverlayPath(dir, "lapras")
	if err != nil {
		t.Fatalf("valid landscape: %v", err)
	}
	if path != filepath.Join(dir, "settings.lapras.yaml") {
		t.Fatalf("unexpected path: %q", path)
	}
}

func TestOverlayPathRejectsUnsafeTokens(t *testing.T) {
	t.Parallel()
	// OverlayPath validates the token grammar itself and, as defence in depth,
	// containment; a separator, a dot segment, or a climbing token is rejected.
	for _, token := range []string{"a/b", "..", "../evil", strings.Repeat("../", 8) + "etc/passwd"} {
		if _, err := layers.OverlayPath("/etc/config", token); err == nil {
			t.Fatalf("%q must be rejected", token)
		}
	}
}
