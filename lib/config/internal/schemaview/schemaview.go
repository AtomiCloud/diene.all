// Package schemaview normalizes an authored draft-2020-12 JSON Schema into a
// single generic JSON value tree and answers the canonical-key questions the
// loader asks of it: which property spellings an instance location accepts,
// whether two spellings collide under the family canonical rule, and how to
// rewrite an instance's keys to the schema's spellings.
//
// Working from the normalized tree is what makes the R14 canonical contract
// hold. An author may legally build a fragment from typed Go containers (for
// example map[string]map[string]any), and a schema may route its object shape
// through $defs plus a local $ref or through allOf composition. Walking the
// authoring containers with direct type assertions would silently skip all of
// those, while the compiler saw the marshalled document — so collision detection
// and alignment run on exactly the document that is compiled.
//
// Reference resolution is local only: a JSON Pointer is resolved against this
// document (decoding the ~1 and ~0 escapes) and nothing is ever fetched. A
// reference cycle terminates because each node is expanded at most once.
//
// It is an internal package with an exported, black-box-testable API, not part
// of the public config surface.
package schemaview

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// rootPath labels a collision that applies to the schema root rather than a
// nested location.
const rootPath = "(root)"

// Normalize re-encodes an authored schema into the generic JSON value tree
// (map[string]any, []any, float64, string, bool, nil) that the compiler also
// consumes. A cyclic or unencodable schema fails fast here, because json.Marshal
// rejects it, which keeps the loader's fail-fast authoring-fault behavior.
func Normalize(schema map[string]any) (map[string]any, error) {
	raw, marshalErr := json.Marshal(schema)
	normalized := map[string]any{}
	decodeErr := json.Unmarshal(raw, &normalized)
	if joined := errors.Join(marshalErr, decodeErr); joined != nil {
		return nil, joined
	}
	return normalized, nil
}

// Document is a normalized schema that resolves local references against itself.
type Document struct {
	root map[string]any
}

// NewDocument wraps an already-normalized schema root; pass the result of
// [Normalize] so every walk sees generic JSON containers.
func NewDocument(root map[string]any) Document { return Document{root: root} }

// Root returns the normalized schema root this document resolves against.
func (d Document) Root() map[string]any { return d.root }

// Position is the set of schema nodes that all constrain one instance location:
// a node itself plus every node reached from it through local references and
// composition keywords.
type Position []map[string]any

// CompositionKeywords are the keywords whose subschemas constrain the SAME
// instance location as their parent, so their properties join the parent's
// canonical view. "not" is deliberately absent: a negated branch's spellings are
// not spellings the location accepts, though [Document.Walk] still inspects it.
//
// The conditional branches ("if", "then", "else") are unioned unconditionally
// rather than evaluated, which is deliberately conservative: the union can only
// widen the accepted spellings, and any canonical ambiguity it exposes is
// rejected rather than resolved by chance. The compiler remains authoritative
// for whether a branch actually applies.
func CompositionKeywords() []string {
	return []string{"allOf", "anyOf", "oneOf", "if", "then", "else"}
}

// DependentCompositionKeywords are keywords holding an object of named
// subschemas that each constrain the SAME instance location as their parent when
// their trigger property is present. Like the conditional branches they are
// unioned conservatively; an ambiguity the union exposes rejects.
func DependentCompositionKeywords() []string {
	return []string{"dependentSchemas"}
}

// NamedSubschemaKeywords are keywords holding an object of named subschemas.
func NamedSubschemaKeywords() []string {
	return []string{"properties", "patternProperties", "dependentSchemas", "$defs", "definitions"}
}

// SingleSubschemaKeywords are keywords holding exactly one subschema.
func SingleSubschemaKeywords() []string {
	return []string{
		"additionalProperties", "unevaluatedProperties", "propertyNames",
		"items", "unevaluatedItems", "additionalItems", "contains",
		"not", "if", "then", "else",
	}
}

// ListSubschemaKeywords are keywords holding an ordered list of subschemas.
func ListSubschemaKeywords() []string {
	return []string{"allOf", "anyOf", "oneOf", "prefixItems"}
}

// Pointer resolves a local JSON Pointer reference ("#", "#/$defs/Name") against
// the document, decoding the ~1 and ~0 escapes in that order per RFC 6901. A
// non-local reference, a malformed pointer, or a missing target reports false;
// nothing is fetched over the network.
func (d Document) Pointer(reference string) (map[string]any, bool) {
	if reference == "#" {
		return d.root, true
	}
	rest, isLocal := strings.CutPrefix(reference, "#/")
	if !isLocal {
		return nil, false
	}
	var current any = d.root
	for token := range strings.SplitSeq(rest, "/") {
		token = strings.ReplaceAll(token, "~1", "/")
		token = strings.ReplaceAll(token, "~0", "~")
		switch node := current.(type) {
		case map[string]any:
			value, found := node[token]
			if !found {
				return nil, false
			}
			current = value
		case []any:
			index, err := strconv.Atoi(token)
			if err != nil || index < 0 || index >= len(node) {
				return nil, false
			}
			current = node[index]
		default:
			return nil, false
		}
	}
	target, isObject := current.(map[string]any)
	return target, isObject
}

// Expand resolves a position into every schema node constraining the same
// instance location: the nodes given, their local $ref targets, and their
// composition branches, transitively. Reference cycles terminate because each
// node is expanded at most once.
func (d Document) Expand(position Position) Position {
	expanded := make(Position, 0, len(position))
	seen := map[uintptr]bool{}
	for _, node := range position {
		expanded = d.ExpandInto(expanded, node, seen)
	}
	return expanded
}

// ExpandInto appends node and everything it composes to expanded, skipping any
// node already recorded in seen. It is exported so the expansion logic has an
// external black-box test surface, per the zero-private-logic rule.
func (d Document) ExpandInto(expanded Position, node map[string]any, seen map[uintptr]bool) Position {
	if node == nil {
		return expanded
	}
	identity := reflect.ValueOf(node).Pointer()
	if seen[identity] {
		return expanded
	}
	seen[identity] = true
	expanded = append(expanded, node)

	if reference, isString := node["$ref"].(string); isString {
		if target, found := d.Pointer(reference); found {
			expanded = d.ExpandInto(expanded, target, seen)
		}
	}
	for _, keyword := range CompositionKeywords() {
		switch branch := node[keyword].(type) {
		case map[string]any:
			expanded = d.ExpandInto(expanded, branch, seen)
		case []any:
			for _, item := range branch {
				if child, isObject := item.(map[string]any); isObject {
					expanded = d.ExpandInto(expanded, child, seen)
				}
			}
		default:
			// An absent or boolean composition branch declares no properties.
		}
	}
	for _, keyword := range DependentCompositionKeywords() {
		declared, isObject := node[keyword].(map[string]any)
		if !isObject {
			continue
		}
		for _, trigger := range SortedNames(declared) {
			if child, isChildObject := declared[trigger].(map[string]any); isChildObject {
				expanded = d.ExpandInto(expanded, child, seen)
			}
		}
	}
	return expanded
}

// SortedNames returns the keys of a named-subschema object in sorted order, so
// every traversal and report is deterministic.
func SortedNames(declared map[string]any) []string {
	names := make([]string, 0, len(declared))
	for name := range declared {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// Properties maps each authored property name an expanded position declares to
// the position describing that property's value, unioning every branch that
// declares the same name. EVERY declared name is indexed, including one whose
// value is a boolean schema (`"cache_region": true`): the name still occupies a
// canonical spelling, so it must take part in collision detection and alignment
// even though it carries no subschema to recurse into.
func Properties(position Position) map[string]Position {
	properties := map[string]Position{}
	for _, node := range position {
		declared, isObject := node["properties"].(map[string]any)
		if !isObject {
			continue
		}
		for _, name := range SortedNames(declared) {
			entry := properties[name]
			if child, isChildObject := declared[name].(map[string]any); isChildObject {
				entry = append(entry, child)
			}
			properties[name] = entry
		}
	}
	return properties
}

// PatternProperties returns the subschemas whose patternProperties regex matches
// name. An uncompilable pattern is skipped: the compiler is authoritative for
// rejecting it, and alignment must not fail on a schema the compiler accepts.
func PatternProperties(position Position, name string) Position {
	matched := make(Position, 0, len(position))
	for _, node := range position {
		declared, isObject := node["patternProperties"].(map[string]any)
		if !isObject {
			continue
		}
		for _, pattern := range SortedNames(declared) {
			child, isChildObject := declared[pattern].(map[string]any)
			if !isChildObject {
				continue
			}
			expression, err := regexp.Compile(pattern)
			if err != nil || !expression.MatchString(name) {
				continue
			}
			matched = append(matched, child)
		}
	}
	return matched
}

// AdditionalProperties returns the fallback subschemas that constrain an
// instance key which neither properties nor patternProperties describes.
func AdditionalProperties(position Position) Position {
	fallback := make(Position, 0, len(position))
	for _, node := range position {
		if child, isObject := node["additionalProperties"].(map[string]any); isObject {
			fallback = append(fallback, child)
		}
	}
	return fallback
}

// Items returns the position constraining the array element at index. Draft
// 2020-12 splits tuple and list validation: inside prefixItems the element is
// constrained by exactly that index's schema, and only elements past prefixItems
// fall to the branch's shared items schema. Each branch is decided on its own.
func Items(position Position, index int) Position {
	elements := make(Position, 0, len(position))
	for _, node := range position {
		if prefixItems, isList := node["prefixItems"].([]any); isList && index < len(prefixItems) {
			if child, isObject := prefixItems[index].(map[string]any); isObject {
				elements = append(elements, child)
			}
			continue
		}
		if items, isObject := node["items"].(map[string]any); isObject {
			elements = append(elements, items)
		}
	}
	return elements
}

// NameIndex maps each canonical property form an expanded position accepts to
// the authored spelling to align onto. Names are indexed in sorted order, so a
// residual collision resolves to the same winner on every run.
func NameIndex(properties map[string]Position) map[string]string {
	names := make([]string, 0, len(properties))
	for name := range properties {
		names = append(names, name)
	}
	slices.Sort(names)
	index := make(map[string]string, len(names))
	for _, name := range names {
		canonical := coreutils.CanonicalConfigKey(name)
		if _, taken := index[canonical]; !taken {
			index[canonical] = name
		}
	}
	return index
}

// Align rewrites instance's keys to the property spellings position accepts,
// matching snake, kebab, camel, and Pascal under the core-utils canonical rule
// and recursing into child objects and array elements — including through local
// references and composition. Keys the schema does not describe are preserved
// unchanged. It terminates on a recursive schema because it descends the finite
// instance rather than the schema.
func (d Document) Align(position Position, instance map[string]any) map[string]any {
	expanded := d.Expand(position)
	properties := Properties(expanded)
	index := NameIndex(properties)

	result := make(map[string]any, len(instance))
	for key, value := range instance {
		target := key
		if name, matched := index[coreutils.CanonicalConfigKey(key)]; matched {
			target = name
		}
		result[target] = d.AlignValue(ValuePosition(expanded, target), value)
	}
	return result
}

// ValuePosition returns every schema constraining the value of instance key name,
// unioning each expanded node's own applicability. Applicability is decided PER
// NODE because that is how draft-2020-12 defines it: when one allOf branch
// declares the key and another does not, the second branch still applies its own
// additionalProperties to that key, so both constrain the value.
func ValuePosition(expanded Position, name string) Position {
	child := make(Position, 0, len(expanded))
	for _, node := range expanded {
		child = append(child, NodeValuePosition(node, name)...)
	}
	return child
}

// NodeValuePosition returns the subschemas of ONE node constraining the value of
// instance key name: its properties entry when it declares one, every matching
// patternProperties entry, and additionalProperties only when this node describes
// the key by neither. A name declared with a boolean schema still counts as
// described, so this node's additionalProperties does not take over.
func NodeValuePosition(node map[string]any, name string) Position {
	single := Position{node}
	declared, isDeclared := Properties(single)[name]
	child := make(Position, 0, len(declared)+1)
	child = append(child, declared...)
	patterns := PatternProperties(single, name)
	child = append(child, patterns...)
	if !isDeclared && len(patterns) == 0 {
		child = append(child, AdditionalProperties(single)...)
	}
	return child
}

// AlignValue aligns one instance value against the position describing it,
// recursing into objects and array elements and returning anything else
// unchanged.
func (d Document) AlignValue(position Position, value any) any {
	if len(position) == 0 {
		return value
	}
	switch typed := value.(type) {
	case map[string]any:
		return d.Align(position, typed)
	case []any:
		expanded := d.Expand(position)
		aligned := make([]any, len(typed))
		for elementIndex, element := range typed {
			aligned[elementIndex] = d.AlignValue(Items(expanded, elementIndex), element)
		}
		return aligned
	default:
		return value
	}
}

// Collision reports the first canonical property-name collision anywhere in the
// document: two different spellings sharing a canonical form within one location's
// combined view (its own properties plus those of its local references and
// composition branches). Every subschema location is inspected, including
// definitions nothing references, so an authoring fault cannot hide in an unused
// $defs entry. Such a schema cannot be aligned deterministically, so the loader
// rejects it before validating.
func (d Document) Collision() (location, detail string, collided bool) {
	return d.Walk(d.root, "")
}

// Walk is the structural recursion behind [Document.Collision]: it checks the
// combined view at node, then descends every subschema-bearing keyword in a
// deterministic order. The normalized document is a finite tree, so the walk
// always terminates. It is exported so the traversal has an external black-box
// test surface.
func (d Document) Walk(node map[string]any, prefix string) (location, detail string, collided bool) {
	if at, why, found := d.PositionCollision(Position{node}, prefix); found {
		return at, why, true
	}
	for _, keyword := range NamedSubschemaKeywords() {
		declared, isObject := node[keyword].(map[string]any)
		if !isObject {
			continue
		}
		names := make([]string, 0, len(declared))
		for name := range declared {
			names = append(names, name)
		}
		slices.Sort(names)
		for _, name := range names {
			child, isChildObject := declared[name].(map[string]any)
			if !isChildObject {
				continue
			}
			if at, why, found := d.Walk(child, Join(prefix, keyword, name)); found {
				return at, why, true
			}
		}
	}
	for _, keyword := range SingleSubschemaKeywords() {
		child, isObject := node[keyword].(map[string]any)
		if !isObject {
			continue
		}
		if at, why, found := d.Walk(child, Join(prefix, keyword, "")); found {
			return at, why, true
		}
	}
	for _, keyword := range ListSubschemaKeywords() {
		list, isList := node[keyword].([]any)
		if !isList {
			continue
		}
		for index, item := range list {
			child, isObject := item.(map[string]any)
			if !isObject {
				continue
			}
			if at, why, found := d.Walk(child, Join(prefix, keyword, strconv.Itoa(index))); found {
				return at, why, true
			}
		}
	}
	return "", "", false
}

// PositionCollision reports whether the combined view of position declares two
// different property spellings sharing one canonical form. Names are compared in
// sorted order so the reported pair is deterministic.
func (d Document) PositionCollision(position Position, prefix string) (location, detail string, collided bool) {
	properties := Properties(d.Expand(position))
	names := make([]string, 0, len(properties))
	for name := range properties {
		names = append(names, name)
	}
	slices.Sort(names)

	seen := make(map[string]string, len(names))
	for _, name := range names {
		canonical := coreutils.CanonicalConfigKey(name)
		if other, taken := seen[canonical]; taken {
			at := prefix
			if at == "" {
				at = rootPath
			}
			return at, fmt.Sprintf("schema properties %q and %q at %s share the canonical form %q", other, name, at, canonical), true
		}
		seen[canonical] = name
	}
	return "", "", false
}

// Join renders the location path of a subschema. A property keeps the dotted
// instance path callers recognise ("app.landscape") and an items schema appends
// "[]", while every other keyword is shown in angle brackets ("<$defs:Widget>",
// "<allOf:1>") because it names a schema location rather than an instance one.
func Join(prefix, keyword, name string) string {
	switch keyword {
	case "properties":
		if prefix == "" {
			return name
		}
		return prefix + "." + name
	case "items":
		return prefix + "[]"
	default:
		label := "<" + keyword
		if name != "" {
			label += ":" + name
		}
		return prefix + label + ">"
	}
}
