// Package collision detects sibling configuration keys whose canonical
// (separator- and case-insensitive) forms collide, within a single tree and
// recursively through nested objects and arrays of objects. It lets the loader
// fail closed on ambiguous input rather than depend on Go map iteration order.
// It is an internal package with an exported, black-box-testable API.
package collision

import (
	"fmt"
	"slices"
	"strconv"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"gopkg.in/yaml.v3"
)

// rootPath labels a collision among the top-level keys.
const rootPath = "(root)"

// Entry is one effective key/value pair of a mapping node after YAML merge (<<)
// keys are resolved, preserving the authored key spelling so a canonical
// collision among effective siblings can still be reported.
type Entry struct {
	// Key is the authored key spelling (e.g. cacheRegion), not its canonical form.
	Key string
	// Value is the mapping value node the key resolves to.
	Value *yaml.Node
}

// DetectYAML parses raw YAML into a mapping-preserving node tree and reports the
// first sibling-key canonical collision, recursing through mappings and sequence
// items and resolving YAML merge (<<) keys so an anchored key merged next to an
// explicit case-only variant is caught. It must run BEFORE Viper consumes the
// document, because Viper lowercases keys and would collapse case-only aliases
// (myKey and MyKey) — and pick a merge winner by map iteration — before they can
// be seen. A document that does not parse yields no collision — the caller's own
// parser (Viper) is the authority that surfaces a malformed document.
func DetectYAML(content []byte) (location, message string, collided bool) {
	var root yaml.Node
	if yaml.Unmarshal(content, &root) != nil {
		return "", "", false
	}
	return WalkNode(&root, "", map[*yaml.Node]bool{})
}

// Resolve follows a chain of YAML alias nodes to the anchored node they point at,
// so a merge source or value spelled as an alias is handled like the node it
// names. A nil node resolves to nil.
func Resolve(node *yaml.Node) *yaml.Node {
	for node != nil && node.Kind == yaml.AliasNode {
		node = node.Alias
	}
	return node
}

// MergeSources resolves a merge (<<) value into the mapping nodes it contributes:
// a single alias yields one mapping, and a sequence yields each mapping it lists
// (earlier entries take precedence per the YAML merge spec). Non-mapping sources
// contribute nothing.
func MergeSources(value *yaml.Node) []*yaml.Node {
	resolved := Resolve(value)
	if resolved == nil {
		return nil
	}
	//nolint:exhaustive // only mapping and sequence merge values contribute keys.
	switch resolved.Kind {
	case yaml.MappingNode:
		return []*yaml.Node{resolved}
	case yaml.SequenceNode:
		sources := make([]*yaml.Node, 0, len(resolved.Content))
		for _, item := range resolved.Content {
			if mapping := Resolve(item); mapping != nil && mapping.Kind == yaml.MappingNode {
				sources = append(sources, mapping)
			}
		}
		return sources
	default:
		return nil
	}
}

// MergedEntries returns the effective entries of a mapping node with YAML merge
// (<<) keys resolved under merge precedence: an explicit key wins over a merged
// one, and an earlier merge source wins over a later one, both compared by exact
// authored spelling (a case-only variant is therefore an additional effective
// sibling, not a merge winner). visited guards against cyclic merge anchors so
// resolution always terminates.
func MergedEntries(node *yaml.Node, visited map[*yaml.Node]bool) []Entry {
	explicit := make([]Entry, 0, len(node.Content)/2)
	var merges []*yaml.Node
	for index := 0; index+1 < len(node.Content); index += 2 {
		keyNode := node.Content[index]
		if keyNode.Tag == "!!merge" || keyNode.Value == "<<" {
			merges = append(merges, node.Content[index+1])
			continue
		}
		explicit = append(explicit, Entry{Key: keyNode.Value, Value: node.Content[index+1]})
	}
	seen := make(map[string]bool, len(explicit))
	result := make([]Entry, 0, len(explicit))
	for _, entry := range explicit {
		// Every explicit key is kept; an exact-duplicate authored key (if the
		// parser preserves one) is left for the downstream canonical check to
		// reject rather than silently dropped here.
		seen[entry.Key] = true
		result = append(result, entry)
	}
	for _, mergeValue := range merges {
		for _, source := range MergeSources(mergeValue) {
			if visited[source] {
				continue
			}
			visited[source] = true
			for _, entry := range MergedEntries(source, visited) {
				if !seen[entry.Key] {
					seen[entry.Key] = true
					result = append(result, entry)
				}
			}
		}
	}
	return result
}

// WalkNode is the recursive core of [DetectYAML], reporting collisions relative
// to prefix. It is exported so the node-walk logic has an external black-box test
// surface. Mapping keys are visited in document order after merge resolution, so
// the report is deterministic; visited terminates cyclic anchors.
func WalkNode(node *yaml.Node, prefix string, visited map[*yaml.Node]bool) (location, message string, collided bool) {
	node = Resolve(node)
	if node == nil || visited[node] {
		return "", "", false
	}
	visited[node] = true
	//nolint:exhaustive // the default case covers scalar, alias, and empty nodes.
	switch node.Kind {
	case yaml.DocumentNode:
		for _, child := range node.Content {
			if childLocation, childMessage, ok := WalkNode(child, prefix, visited); ok {
				return childLocation, childMessage, true
			}
		}
	case yaml.MappingNode:
		entries := MergedEntries(node, map[*yaml.Node]bool{})
		seen := make(map[string]string, len(entries))
		for _, entry := range entries {
			canonical := coreutils.CanonicalConfigKey(entry.Key)
			if other, ok := seen[canonical]; ok {
				at := prefix
				if at == "" {
					at = rootPath
				}
				return at, fmt.Sprintf("keys %q and %q at %s share the canonical form %q", other, entry.Key, at, canonical), true
			}
			seen[canonical] = entry.Key
		}
		for _, entry := range entries {
			path := entry.Key
			if prefix != "" {
				path = prefix + "." + entry.Key
			}
			if childLocation, childMessage, ok := WalkNode(entry.Value, path, visited); ok {
				return childLocation, childMessage, true
			}
		}
	case yaml.SequenceNode:
		for index, child := range node.Content {
			if childLocation, childMessage, ok := WalkNode(child, prefix+"["+strconv.Itoa(index)+"]", visited); ok {
				return childLocation, childMessage, true
			}
		}
	default:
		// Scalars and other node kinds carry no sibling keys.
	}
	return "", "", false
}

// Detect walks tree and returns the location path and a human message for the
// first sibling-key canonical collision, or ("", "", false) when none exist.
// Keys are visited in sorted order, so the reported collision is deterministic.
func Detect(tree map[string]any) (location, message string, collided bool) {
	return DetectAt(tree, "")
}

// DetectAt is the recursive core of [Detect], reporting collisions relative to
// prefix. It is exported so the detection logic has an external black-box test
// surface.
func DetectAt(node map[string]any, prefix string) (location, message string, collided bool) {
	keys := make([]string, 0, len(node))
	for key := range node {
		keys = append(keys, key)
	}
	slices.Sort(keys)

	seen := make(map[string]string, len(keys))
	for _, key := range keys {
		canonical := coreutils.CanonicalConfigKey(key)
		if other, ok := seen[canonical]; ok {
			at := prefix
			if at == "" {
				at = rootPath
			}
			return at, fmt.Sprintf("keys %q and %q at %s share the canonical form %q", other, key, at, canonical), true
		}
		seen[canonical] = key
	}

	for _, key := range keys {
		path := key
		if prefix != "" {
			path = prefix + "." + key
		}
		switch child := node[key].(type) {
		case map[string]any:
			if childLocation, childMessage, ok := DetectAt(child, path); ok {
				return childLocation, childMessage, true
			}
		case []any:
			for index, element := range child {
				nested, isMap := element.(map[string]any)
				if !isMap {
					continue
				}
				if childLocation, childMessage, ok := DetectAt(nested, path+"["+strconv.Itoa(index)+"]"); ok {
					return childLocation, childMessage, true
				}
			}
		default:
			// Scalar values carry no sibling keys.
		}
	}
	return "", "", false
}
