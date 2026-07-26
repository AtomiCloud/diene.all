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

// DetectYAML parses raw YAML into a mapping-preserving node tree and reports the
// first sibling-key canonical collision, recursing through mappings and sequence
// items. It must run BEFORE Viper consumes the document, because Viper lowercases
// keys and would collapse case-only aliases (myKey and MyKey) before they can be
// seen. A document that does not parse yields no collision — the caller's own
// parser (Viper) is the authority that surfaces a malformed document.
func DetectYAML(content []byte) (location, message string, collided bool) {
	var root yaml.Node
	if yaml.Unmarshal(content, &root) != nil {
		return "", "", false
	}
	return WalkNode(&root, "")
}

// WalkNode is the recursive core of [DetectYAML], reporting collisions relative
// to prefix. It is exported so the node-walk logic has an external black-box test
// surface. Mapping keys are visited in document order, so the report is
// deterministic.
func WalkNode(node *yaml.Node, prefix string) (location, message string, collided bool) {
	//nolint:exhaustive // the default case covers scalar, alias, and empty nodes.
	switch node.Kind {
	case yaml.DocumentNode:
		for _, child := range node.Content {
			if childLocation, childMessage, ok := WalkNode(child, prefix); ok {
				return childLocation, childMessage, true
			}
		}
	case yaml.MappingNode:
		seen := make(map[string]string, len(node.Content)/2)
		for index := 0; index+1 < len(node.Content); index += 2 {
			key := node.Content[index].Value
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
		for index := 0; index+1 < len(node.Content); index += 2 {
			key := node.Content[index].Value
			path := key
			if prefix != "" {
				path = prefix + "." + key
			}
			if childLocation, childMessage, ok := WalkNode(node.Content[index+1], path); ok {
				return childLocation, childMessage, true
			}
		}
	case yaml.SequenceNode:
		for index, child := range node.Content {
			if childLocation, childMessage, ok := WalkNode(child, prefix+"["+strconv.Itoa(index)+"]"); ok {
				return childLocation, childMessage, true
			}
		}
	default:
		// Scalars, aliases, and other node kinds carry no sibling keys.
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
