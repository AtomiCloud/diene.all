package collision_test

import (
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/collision"
)

func TestDetectYAMLCaseAndSeparatorCollisions(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"case-only":       "demo:\n  myKey: 1\n  MyKey: 2\n",
		"kebab-vs-camel":  "demo:\n  cache-region: a\n  cacheRegion: b\n",
		"snake-vs-pascal": "svc:\n  data_dir: a\n  DataDir: b\n",
		"root-level":      "app: 1\nApp: 2\n",
	}
	for name, document := range cases {
		location, message, collided := collision.DetectYAML([]byte(document))
		if !collided {
			t.Fatalf("%s: expected a collision", name)
		}
		if location == "" || !strings.Contains(message, "canonical") {
			t.Fatalf("%s: unhelpful report %q / %q", name, location, message)
		}
	}
}

func TestDetectYAMLNestedAndArrayCollisions(t *testing.T) {
	t.Parallel()
	nested := "outer:\n  inner:\n    a-b: 1\n    aB: 2\n"
	if location, _, collided := collision.DetectYAML([]byte(nested)); !collided || location != "outer.inner" {
		t.Fatalf("nested collision location wrong: %q %v", location, collided)
	}
	array := "list:\n  - name: ok\n  - region: 1\n    Region: 2\n"
	if location, _, collided := collision.DetectYAML([]byte(array)); !collided || location != "list[1]" {
		t.Fatalf("array-object collision location wrong: %q %v", location, collided)
	}
}

func TestDetectYAMLAcceptsDistinctKeys(t *testing.T) {
	t.Parallel()
	if _, _, collided := collision.DetectYAML([]byte("demo:\n  region: a\n  secret: b\n  list:\n    - x: 1\n")); collided {
		t.Fatal("distinct keys must not collide")
	}
}

func TestDetectYAMLMalformedReportsNoCollision(t *testing.T) {
	t.Parallel()
	if _, _, collided := collision.DetectYAML([]byte("\t not: [valid")); collided {
		t.Fatal("a malformed document defers to the caller's parser, reporting no collision")
	}
}

func TestDetectMapCollisions(t *testing.T) {
	t.Parallel()
	// The map form is used for the env-produced tree and public bypass maps.
	env := map[string]any{"cache_region": "a", "cacheregion": "b"}
	if location, _, collided := collision.Detect(env); !collided || location != "(root)" {
		t.Fatalf("env map collision wrong: %q %v", location, collided)
	}
	nested := map[string]any{"demo": map[string]any{"data-dir": 1, "dataDir": 2}}
	if location, _, collided := collision.Detect(nested); !collided || location != "demo" {
		t.Fatalf("nested map collision wrong: %q %v", location, collided)
	}
	arrayObject := map[string]any{"list": []any{"scalar", map[string]any{"a_b": 1, "aB": 2}}}
	if location, _, collided := collision.Detect(arrayObject); !collided || location != "list[1]" {
		t.Fatalf("array-object map collision wrong: %q %v", location, collided)
	}
	if _, _, collided := collision.Detect(map[string]any{"a": 1, "b": map[string]any{"c": 2}}); collided {
		t.Fatal("distinct map keys must not collide")
	}
}
