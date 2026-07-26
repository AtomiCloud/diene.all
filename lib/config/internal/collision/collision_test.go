package collision_test

import (
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/collision"
	"gopkg.in/yaml.v3"
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

func TestDetectYAMLMergeAliasCollision(t *testing.T) {
	t.Parallel()
	// A merged anchored key and an explicit case-only variant are effective
	// siblings that Viper would otherwise collapse and pick between by map order.
	document := "defaults: &d\n  cacheRegion: first\ndemo:\n  <<: *d\n  CacheRegion: second\n"
	location, message, collided := collision.DetectYAML([]byte(document))
	if !collided || location != "demo" || !strings.Contains(message, "canonical") {
		t.Fatalf("merge-alias collision not caught: %q %q %v", location, message, collided)
	}
}

func TestDetectYAMLMergeSequenceCollision(t *testing.T) {
	t.Parallel()
	document := "a: &a\n  region: 1\nb: &b\n  REGION: 2\ndemo:\n  <<: [*a, *b]\n"
	location, _, collided := collision.DetectYAML([]byte(document))
	if !collided || location != "demo" {
		t.Fatalf("merge-sequence collision not caught: %q %v", location, collided)
	}
}

func TestDetectYAMLMergeAnchorInternalCollisionCaught(t *testing.T) {
	t.Parallel()
	// A collision inside an anchor's own definition is caught at the definition
	// site, so merging that anchor elsewhere cannot smuggle it past the detector.
	document := "defaults: &d\n  nested:\n    aB: 1\n    a-b: 2\ndemo:\n  <<: *d\n"
	if location, _, collided := collision.DetectYAML([]byte(document)); !collided || location != "defaults.nested" {
		t.Fatalf("anchor-internal collision wrong: %q %v", location, collided)
	}
}

func TestDetectYAMLExplicitShadowsMergedKey(t *testing.T) {
	t.Parallel()
	// An explicit key with the exact spelling shadows the merged one (YAML merge
	// precedence), so there is exactly one effective key and no collision.
	document := "defaults: &d\n  region: fromMerge\ndemo:\n  <<: *d\n  region: explicit\n"
	if _, _, collided := collision.DetectYAML([]byte(document)); collided {
		t.Fatal("an exact-spelling explicit key shadows the merged key without colliding")
	}
}

func TestDetectYAMLMergeAddsDistinctKeys(t *testing.T) {
	t.Parallel()
	document := "defaults: &d\n  extra: 1\ndemo:\n  <<: *d\n  region: 2\n"
	if _, _, collided := collision.DetectYAML([]byte(document)); collided {
		t.Fatal("a merge adding a distinct key must not collide")
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

func TestResolveFollowsAliasChain(t *testing.T) {
	t.Parallel()
	target := &yaml.Node{Kind: yaml.MappingNode}
	alias := &yaml.Node{Kind: yaml.AliasNode, Alias: target}
	chained := &yaml.Node{Kind: yaml.AliasNode, Alias: alias}
	if collision.Resolve(chained) != target {
		t.Fatal("an alias chain must resolve to its anchored node")
	}
	if collision.Resolve(nil) != nil {
		t.Fatal("a nil node resolves to nil")
	}
}

func TestMergeSourcesShapes(t *testing.T) {
	t.Parallel()
	scalar := &yaml.Node{Kind: yaml.ScalarNode, Value: "x"}
	if collision.MergeSources(scalar) != nil {
		t.Fatal("a scalar merge value contributes no sources")
	}
	nilAlias := &yaml.Node{Kind: yaml.AliasNode, Alias: nil}
	if collision.MergeSources(nilAlias) != nil {
		t.Fatal("an empty alias contributes no sources")
	}
	mapping := &yaml.Node{Kind: yaml.MappingNode}
	if got := collision.MergeSources(mapping); len(got) != 1 || got[0] != mapping {
		t.Fatalf("a mapping merge value contributes itself: %v", got)
	}
	sequence := &yaml.Node{Kind: yaml.SequenceNode, Content: []*yaml.Node{mapping, scalar}}
	if got := collision.MergeSources(sequence); len(got) != 1 || got[0] != mapping {
		t.Fatalf("a sequence contributes only its mapping items: %v", got)
	}
}

func TestMergedEntriesTerminatesOnCyclicMerge(t *testing.T) {
	t.Parallel()
	self := &yaml.Node{Kind: yaml.MappingNode}
	aliasSelf := &yaml.Node{Kind: yaml.AliasNode, Alias: self}
	mergeKey := &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!merge", Value: "<<"}
	self.Content = []*yaml.Node{mergeKey, aliasSelf}
	if entries := collision.MergedEntries(self, map[*yaml.Node]bool{}); len(entries) != 0 {
		t.Fatalf("a self-merging mapping resolves to no effective keys: %v", entries)
	}
}

func TestWalkNodeTerminatesOnCyclicAlias(t *testing.T) {
	t.Parallel()
	sequence := &yaml.Node{Kind: yaml.SequenceNode}
	alias := &yaml.Node{Kind: yaml.AliasNode, Alias: sequence}
	sequence.Content = []*yaml.Node{alias}
	if _, _, collided := collision.WalkNode(sequence, "", map[*yaml.Node]bool{}); collided {
		t.Fatal("a cyclic alias must terminate without reporting a collision")
	}
	if _, _, collided := collision.WalkNode(&yaml.Node{Kind: yaml.AliasNode, Alias: nil}, "", map[*yaml.Node]bool{}); collided {
		t.Fatal("an empty alias node walks to nothing")
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
