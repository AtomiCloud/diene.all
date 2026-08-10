package schemaview

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/resource"
)

// Dialect is the only meta-schema the supported subset accepts at the composed
// root. It is the same URI the public config.Draft2020 constant carries; the
// internal packages cannot import the public one, and an external test asserts
// the two never drift apart.
const Dialect = "https://json-schema.org/draft/2020-12/schema"

// DeniedKeywords maps every keyword the supported subset refuses at a schema
// node to the reason an author is given. Each is denied because it would either
// make validation depend on the authored SPELLING of a key — which the family's
// canonical-key contract says is not meaningful — or silently assert nothing.
//
// The checks apply only at role-proven schema nodes: the same word appearing as
// data inside "const", "enum", "default", "examples", or an unknown annotation
// is ordinary content and is never denied.
func DeniedKeywords() map[string]string {
	return map[string]string{
		"patternProperties": "key patterns match the authored spelling, which configuration keys do not preserve; use additionalProperties with a value schema, or fixed properties",
		"propertyNames":     "key-name constraints match the authored spelling, which configuration keys do not preserve; use fixed properties",
		"$anchor":           "anchors are outside the supported local pointer reference grammar",
		"$dynamicAnchor":    "dynamic anchors are outside the supported local pointer reference grammar",
		"$dynamicRef":       "dynamic references are outside the supported local pointer reference grammar",
		"$recursiveAnchor":  "recursive anchors are outside the supported local pointer reference grammar",
		"$recursiveRef":     "recursive references are outside the supported local pointer reference grammar",
		"$vocabulary":       "the dialect is fixed, so a custom vocabulary cannot be honored",
		"dependencies":      "the 2020-12 dialect ignores it, so it would assert nothing; use dependentRequired or dependentSchemas",
		"additionalItems":   "the 2020-12 dialect ignores it, so it would assert nothing; use items after prefixItems",
		"contentSchema":     "content assertions are not enabled by this validator, so it would assert nothing",
		"contentEncoding":   "content assertions are not enabled by this validator, so it would assert nothing",
		"contentMediaType":  "content assertions are not enabled by this validator, so it would assert nothing",
	}
}

// Audit enforces the supported draft-2020-12 subset over a normalized composed
// root, before anything is canonicalized or compiled. It builds the approved
// schema-node graph, refuses every denied keyword at a schema node, checks the
// resource identity rules, and resolves every actual reference. Every failure is
// an authoring fault: a plain error naming the schema location.
func Audit(root map[string]any) error {
	if dialect, isString := root["$schema"].(string); !isString || dialect != Dialect {
		return fmt.Errorf("config: schema root must declare $schema %q", Dialect)
	}
	graph := NewGraph(root)
	if err := AuditNodes(root, graph); err != nil {
		return err
	}
	return AuditReferences(graph)
}

// AuditNodes checks the denied-keyword matrix and the "$schema"/"$id" placement
// rules at every approved schema node. It is exported so the audit has an
// external black-box test surface.
func AuditNodes(root map[string]any, graph *Graph) error {
	for _, pointer := range SortedNames(NodesAsAny(graph)) {
		role := graph.Nodes()[pointer]
		node, isObject := Resolve(root, role.Tokens)
		object, isMap := node.(map[string]any)
		if !isObject || !isMap {
			continue
		}
		for _, keyword := range SortedNames(object) {
			if reason, denied := DeniedKeywords()[keyword]; denied {
				return fmt.Errorf("config: unsupported schema construct %q at %s: %s", keyword, pointer, reason)
			}
		}
		if err := AuditIdentity(object, role, pointer); err != nil {
			return err
		}
	}
	return nil
}

// AuditIdentity enforces where a resource identity may be declared: "$schema"
// only at the composed root, and "$id" only on a direct root block mount and
// only at the exact generated value. An authored identity is reported rather
// than overwritten, so the evidence survives.
func AuditIdentity(object map[string]any, role Role, pointer string) error {
	if _, declares := object["$schema"]; declares && len(role.Tokens) != 0 {
		return fmt.Errorf("config: unsupported schema construct %q at %s: only the composed root declares the dialect", "$schema", pointer)
	}
	identity, declares := object["$id"]
	if !declares {
		return nil
	}
	text, isString := identity.(string)
	if !isString {
		return fmt.Errorf("config: unsupported schema construct %q at %s: a resource identity must be a string", "$id", pointer)
	}
	if len(role.Tokens) != 2 || role.Tokens[0] != "properties" {
		return fmt.Errorf("config: unsupported schema construct %q at %s: a resource identity is only generated for a composed block mount", "$id", pointer)
	}
	if expected := resource.BlockID(role.Tokens[1]); text != expected {
		return fmt.Errorf("config: unsupported schema construct %q at %s: expected the generated block resource %q, got %q", "$id", pointer, expected, text)
	}
	return nil
}

// AuditReferences resolves every actual reference against the approved graph.
// A reference must be a supported local pointer, must be declared inside a
// generated block resource rather than the composed root, and must resolve to an
// approved schema node inside that same resource — never to a keyword container,
// an unknown annotation, or data below "const" or "enum".
func AuditReferences(graph *Graph) error {
	for _, reference := range graph.References() {
		source := FormatPointer(reference.Role.Tokens)
		tokens, err := ParsePointer(reference.Value)
		if err != nil {
			return fmt.Errorf("config: unsupported reference at %s: %w", source, err)
		}
		if len(reference.Role.Resource) == 0 {
			return fmt.Errorf("config: unsupported reference %q at %s: only a composed block may declare a reference", reference.Value, source)
		}
		target := make([]string, 0, len(reference.Role.Resource)+len(tokens))
		target = append(target, reference.Role.Resource...)
		target = append(target, tokens...)
		// The target must be an approved schema node AND belong to the same block
		// resource. Both are one condition: a pointer that walks into another
		// resource, a keyword container, an unknown annotation, or data below
		// "const"/"enum" simply is not a reachable schema node of this block.
		role, approved := graph.Node(target)
		if !approved || !EqualTokens(role.Resource, reference.Role.Resource) {
			return fmt.Errorf("config: unsupported reference %q at %s: %s is not an approved schema node inside the block resource %s",
				reference.Value, source, FormatPointer(target), FormatPointer(reference.Role.Resource))
		}
	}
	return nil
}

// Resolve walks tokens from root and returns the value found there. It is the
// read side of the pointer grammar and is exported for direct testing.
func Resolve(root any, tokens []string) (any, bool) {
	current := root
	for _, token := range tokens {
		switch node := current.(type) {
		case map[string]any:
			value, found := node[token]
			if !found {
				return nil, false
			}
			current = value
		case []any:
			position, err := ParseIndex(token)
			if err != nil || position >= len(node) {
				return nil, false
			}
			current = node[position]
		default:
			return nil, false
		}
	}
	return current, true
}

// NodesAsAny renders the graph's node index as a plain map so the shared sorted
// walk can order it deterministically.
func NodesAsAny(graph *Graph) map[string]any {
	nodes := make(map[string]any, len(graph.Nodes()))
	for pointer := range graph.Nodes() {
		nodes[pointer] = nil
	}
	return nodes
}
