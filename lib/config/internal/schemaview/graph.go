package schemaview

import "slices"

// NamedSchemaKeywords hold an object whose every value is a subschema.
func NamedSchemaKeywords() []string {
	return []string{"$defs", "definitions", "properties", "dependentSchemas"}
}

// SingleSchemaKeywords hold exactly one subschema.
func SingleSchemaKeywords() []string {
	return []string{
		"additionalProperties", "unevaluatedProperties",
		"items", "unevaluatedItems", "contains",
		"not", "if", "then", "else",
	}
}

// ListSchemaKeywords hold an ordered list of subschemas.
func ListSchemaKeywords() []string {
	return []string{"allOf", "anyOf", "oneOf", "prefixItems"}
}

// NameBearingKeywords hold a map whose KEYS are configuration key names. Schema
// canonicalization rewrites those keys, so a pointer token indexing one of these
// maps is rewritten with it.
func NameBearingKeywords() []string {
	return []string{"properties", "dependentSchemas", "dependentRequired"}
}

// IsNameBearingKeyword reports whether keyword introduces a map whose keys are
// configuration key names.
func IsNameBearingKeyword(keyword string) bool {
	return slices.Contains(NameBearingKeywords(), keyword)
}

// Role records where an approved schema node sits: its own token path from the
// document root and the token path of the resource it belongs to.
type Role struct {
	// Tokens is the RFC-6901 token path from the document root to the node.
	Tokens []string
	// Resource is the token path of the nearest enclosing resource root, which
	// is the document root until a node declares an "$id".
	Resource []string
}

// Reference is one actual $ref keyword found on an approved schema node. A
// "$ref"-looking key inside opaque data never becomes a Reference, because the
// graph walk never enters data.
type Reference struct {
	// Role is where the referring schema node sits.
	Role Role
	// Value is the authored reference text.
	Value string
}

// Graph is the approved schema-node graph of one normalized document: every
// position the supported draft-2020-12 subset treats as a schema, together with
// the references those positions declare.
//
// Only real schema-bearing edges are entered — "$defs" and "definitions"
// entries, "properties" and "dependentSchemas" values, and the object/array
// applicator children — so data under "const", "enum", "default", or "examples"
// and any unknown annotation stay opaque no matter what their keys look like.
type Graph struct {
	nodes      map[string]Role
	references []Reference
}

// NewGraph walks root and records every approved schema node with its role,
// together with every actual reference.
func NewGraph(root map[string]any) *Graph {
	graph := &Graph{nodes: map[string]Role{}}
	graph.Visit(root, Role{Tokens: []string{}, Resource: []string{}})
	return graph
}

// Nodes returns the approved schema nodes keyed by their rendered pointer.
func (g *Graph) Nodes() map[string]Role { return g.nodes }

// References returns every reference declared on an approved schema node, in
// document order.
func (g *Graph) References() []Reference { return g.references }

// Node returns the role recorded for a token path, if it is an approved schema
// node.
func (g *Graph) Node(tokens []string) (Role, bool) {
	role, found := g.nodes[FormatPointer(tokens)]
	return role, found
}

// Visit records value as an approved schema node at role and descends every
// schema-bearing edge. A boolean is a valid schema and is recorded as a leaf, so
// a reference may legitimately target a boolean "$defs" entry. It is exported so
// the graph walk has an external black-box test surface.
func (g *Graph) Visit(value any, role Role) {
	switch node := value.(type) {
	case bool:
		g.nodes[FormatPointer(role.Tokens)] = role
	case map[string]any:
		if _, declaresID := node["$id"].(string); declaresID {
			role.Resource = slices.Clone(role.Tokens)
		}
		g.nodes[FormatPointer(role.Tokens)] = role
		if reference, isString := node["$ref"].(string); isString {
			g.references = append(g.references, Reference{Role: role, Value: reference})
		}
		for _, keyword := range NamedSchemaKeywords() {
			declared, isObject := node[keyword].(map[string]any)
			if !isObject {
				continue
			}
			keywordTokens := Child(role.Tokens, keyword)
			for _, name := range SortedNames(declared) {
				g.Visit(declared[name], Role{Tokens: Child(keywordTokens, name), Resource: role.Resource})
			}
		}
		for _, keyword := range SingleSchemaKeywords() {
			child, present := node[keyword]
			if !present {
				continue
			}
			g.Visit(child, Role{Tokens: Child(role.Tokens, keyword), Resource: role.Resource})
		}
		for _, keyword := range ListSchemaKeywords() {
			list, isList := node[keyword].([]any)
			if !isList {
				continue
			}
			keywordTokens := Child(role.Tokens, keyword)
			for index, item := range list {
				g.Visit(item, Role{Tokens: Child(keywordTokens, Index(index)), Resource: role.Resource})
			}
		}
	default:
		// Any other value at a schema position is malformed; the compiler reports
		// it as an ordinary schema error rather than the graph guessing.
	}
}
