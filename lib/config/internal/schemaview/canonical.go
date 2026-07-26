package schemaview

import (
	"fmt"
	"slices"
)

// NameArrayKeywords hold an array of configuration key names rather than
// subschemas. Their entries are redundant predicates, not competing map entries,
// so canonical duplicates are stable-deduped instead of reported as a collision.
func NameArrayKeywords() []string { return []string{"required"} }

// DataKeywords hold instance DATA that is COMPARED against the instance, so
// object keys inside them are canonicalized — that is what makes an
// object-valued constraint match an instance spelling the same keys differently.
// Nothing inside is ever treated as a schema. Every other non-schema value is
// opaque and copied byte-for-byte instead; see [CloneOpaque].
func DataKeywords() []string { return []string{"const", "enum"} }

// CloneOpaque returns a deep copy of a value the supported subset treats as
// OPAQUE, preserving every map key exactly as authored. Annotations such as
// "title", "default", "examples", and any unknown vendor extension are ordinary
// content: they are never compared against instance keys, so rewriting their
// keys would corrupt what the author wrote and contradict the documented
// contract. Malformed values at schema positions are carried through the same
// way, so the compiler reports its ordinary error on exactly the authored bytes.
//
// Nothing inside an opaque value is audited, reference-resolved, or
// collision-checked; a key that merely looks like a keyword is just content.
func CloneOpaque(value any) any {
	switch node := value.(type) {
	case map[string]any:
		cloned := make(map[string]any, len(node))
		for name, child := range node {
			cloned[name] = CloneOpaque(child)
		}
		return cloned
	case []any:
		cloned := make([]any, 0, len(node))
		for _, item := range node {
			cloned = append(cloned, CloneOpaque(item))
		}
		return cloned
	default:
		return node
	}
}

// Canonicalize returns the schema the validator actually compiles: a deep copy of
// root in which every NAME position carries its canonical form. Those positions
// are the keys of each "properties", "dependentSchemas", and "dependentRequired"
// map, the string entries of "required" and of each "dependentRequired" value,
// and every object key inside "const" and "enum" data. References are rewritten
// so a pointer through a renamed name map still resolves.
//
// Everything else is copied unchanged, key bytes included: "$defs" and
// "definitions" entry names, formats, every value-domain keyword, and every
// annotation such as "title", "default", "examples", or an unknown vendor
// extension (see [CloneOpaque]). Malformed entries — a non-string in "required",
// a non-array "dependentRequired" value — are preserved exactly so the compiler
// reports its ordinary schema error instead of the canonicalizer silently
// repairing the document.
func Canonicalize(root map[string]any) map[string]any {
	// Canonicalizing an object always yields an object; a failed assertion would
	// be an invariant break, so force it rather than silently drop the schema.
	//nolint:forcetypeassert,revive // guaranteed by the input type; must not fail silently.
	return CanonicalizeNode(root).(map[string]any)
}

// CanonicalizeNode returns the canonical form of one schema node, descending
// only real schema-bearing edges. It is exported so the schema rewrite has an
// external black-box test surface.
func CanonicalizeNode(value any) any {
	node, isObject := value.(map[string]any)
	if !isObject {
		// A boolean schema, or a malformed schema position, is carried through
		// exactly as authored.
		return CloneOpaque(value)
	}
	rewritten := make(map[string]any, len(node))
	for _, keyword := range SortedNames(node) {
		rewritten[keyword] = CanonicalizeKeyword(keyword, node[keyword])
	}
	return rewritten
}

// CanonicalizeKeyword returns the canonical form of one keyword's value,
// dispatching on the role the supported subset gives that keyword.
func CanonicalizeKeyword(keyword string, value any) any {
	switch {
	case keyword == "$ref":
		return CanonicalizeReference(value)
	case keyword == "properties" || keyword == "dependentSchemas":
		return CanonicalizeNameMap(value, CanonicalizeNode)
	case keyword == "dependentRequired":
		return CanonicalizeNameMap(value, CanonicalizeNameArray)
	case slices.Contains(NameArrayKeywords(), keyword):
		return CanonicalizeNameArray(value)
	case slices.Contains(DataKeywords(), keyword):
		return CanonicalizeData(value)
	case keyword == "$defs" || keyword == "definitions":
		return CanonicalizeEntryMap(value)
	case slices.Contains(SingleSchemaKeywords(), keyword):
		return CanonicalizeNode(value)
	case slices.Contains(ListSchemaKeywords(), keyword):
		return CanonicalizeList(value)
	default:
		// An annotation or value-domain keyword is opaque content: it carries no
		// key names to canonicalize, so its own keys are preserved exactly.
		return CloneOpaque(value)
	}
}

// CanonicalizeReference rewrites a supported local pointer so its tokens through
// canonicalized name maps still resolve. A malformed reference is carried
// through unchanged; the audit has already rejected it.
func CanonicalizeReference(value any) any {
	reference, isString := value.(string)
	if !isString {
		return value
	}
	tokens, err := ParsePointer(reference)
	if err != nil {
		return value
	}
	return FormatPointer(CanonicalizePointerTokens(tokens))
}

// CanonicalizeNameMap canonicalizes the KEYS of a name-bearing map and applies
// canonicalizeValue to each value. A later key wins deterministically because the
// keys are visited in sorted order; sibling canonical twins are rejected before
// this runs, so no data is actually lost.
func CanonicalizeNameMap(value any, canonicalizeValue func(any) any) any {
	declared, isObject := value.(map[string]any)
	if !isObject {
		return CloneOpaque(value)
	}
	rewritten := make(map[string]any, len(declared))
	for _, name := range SortedNames(declared) {
		rewritten[CanonicalKey(name)] = canonicalizeValue(declared[name])
	}
	return rewritten
}

// CanonicalizeEntryMap canonicalizes the VALUES of a definition container while
// leaving its entry names alone: a "$defs" name is a schema label, not a
// configuration key, and pointer tokens naming one are not rewritten either.
func CanonicalizeEntryMap(value any) any {
	declared, isObject := value.(map[string]any)
	if !isObject {
		return CloneOpaque(value)
	}
	rewritten := make(map[string]any, len(declared))
	for name, entry := range declared {
		rewritten[name] = CanonicalizeNode(entry)
	}
	return rewritten
}

// CanonicalizeList canonicalizes each element of an applicator list as a schema.
func CanonicalizeList(value any) any {
	list, isList := value.([]any)
	if !isList {
		return CloneOpaque(value)
	}
	rewritten := make([]any, 0, len(list))
	for _, item := range list {
		rewritten = append(rewritten, CanonicalizeNode(item))
	}
	return rewritten
}

// CanonicalizeNameArray canonicalizes the string entries of a name array and
// stable-dedupes the result, keeping first-seen order. A non-string entry is
// preserved unchanged so the compiler reports the ordinary schema error.
func CanonicalizeNameArray(value any) any {
	list, isList := value.([]any)
	if !isList {
		return CloneOpaque(value)
	}
	rewritten := make([]any, 0, len(list))
	seen := make(map[string]bool, len(list))
	for _, entry := range list {
		name, isString := entry.(string)
		if !isString {
			rewritten = append(rewritten, CloneOpaque(entry))
			continue
		}
		canonical := CanonicalKey(name)
		if seen[canonical] {
			continue
		}
		seen[canonical] = true
		rewritten = append(rewritten, canonical)
	}
	return rewritten
}

// CanonicalizeData returns a deep copy of instance-shaped data with every object
// key at every depth replaced by its canonical form, descending arrays. It is
// what makes an object-valued "const" or "enum" compare equal to an instance
// that spells the same keys differently.
//
// It is reserved for exactly those three inputs — "const", "enum", and the
// instance — because they are the only values COMPARED against instance keys.
// Every other non-schema value is opaque; use [CloneOpaque] there.
func CanonicalizeData(value any) any {
	switch node := value.(type) {
	case map[string]any:
		rewritten := make(map[string]any, len(node))
		for _, name := range SortedNames(node) {
			rewritten[CanonicalKey(name)] = CanonicalizeData(node[name])
		}
		return rewritten
	case []any:
		rewritten := make([]any, 0, len(node))
		for _, item := range node {
			rewritten = append(rewritten, CanonicalizeData(item))
		}
		return rewritten
	default:
		return node
	}
}

// CanonicalizeInstance returns the instance the validator actually sees: a deep
// copy of object with every key at every depth, including inside arrays, in
// canonical form. It needs no schema knowledge at all.
func CanonicalizeInstance(object map[string]any) map[string]any {
	// Canonicalizing an object always yields an object; a failed assertion would
	// be an invariant break, so force it rather than silently drop the instance.
	//nolint:forcetypeassert,revive // guaranteed by the input type; must not fail silently.
	return CanonicalizeData(object).(map[string]any)
}

// Collision reports the first place where canonicalizing the schema would
// OVERWRITE data: two distinct spellings sharing a canonical form as sibling
// keys of one "properties", "dependentSchemas", or "dependentRequired" map, or
// of any object nested inside "const" or "enum" data.
//
// Nothing else is reported. Twins across composed branches are legal — under
// canonicalization they name one key and the compiler applies each branch's
// constraints natively — and "required"-style arrays are redundant predicates
// that are deduped rather than rejected.
func Collision(root map[string]any) (location, detail string, collided bool) {
	return CollisionAt(root, []string{})
}

// CollisionAt is the recursive core of [Collision], reporting relative to the
// token path of node. It is exported so the check has an external black-box test
// surface.
func CollisionAt(value any, tokens []string) (location, detail string, collided bool) {
	node, isObject := value.(map[string]any)
	if !isObject {
		return "", "", false
	}
	for _, keyword := range SortedNames(node) {
		child := Child(tokens, keyword)
		switch {
		case IsNameBearingKeyword(keyword):
			declared, isMap := node[keyword].(map[string]any)
			if !isMap {
				continue
			}
			if at, why, found := TwinNames(declared, child); found {
				return at, why, true
			}
			if keyword == "dependentRequired" {
				continue
			}
			for _, name := range SortedNames(declared) {
				if at, why, found := CollisionAt(declared[name], Child(child, name)); found {
					return at, why, true
				}
			}
		case slices.Contains(DataKeywords(), keyword):
			if at, why, found := DataCollision(node[keyword], child); found {
				return at, why, true
			}
		case keyword == "$defs" || keyword == "definitions":
			declared, isMap := node[keyword].(map[string]any)
			if !isMap {
				continue
			}
			for _, name := range SortedNames(declared) {
				if at, why, found := CollisionAt(declared[name], Child(child, name)); found {
					return at, why, true
				}
			}
		case slices.Contains(SingleSchemaKeywords(), keyword):
			if at, why, found := CollisionAt(node[keyword], child); found {
				return at, why, true
			}
		case slices.Contains(ListSchemaKeywords(), keyword):
			list, isList := node[keyword].([]any)
			if !isList {
				continue
			}
			for index, item := range list {
				if at, why, found := CollisionAt(item, Child(child, Index(index))); found {
					return at, why, true
				}
			}
		default:
			// An annotation or value-domain keyword declares no key names.
		}
	}
	return "", "", false
}

// DataCollision reports canonical twins among the sibling keys of every object
// nested inside instance-shaped data, descending arrays.
func DataCollision(value any, tokens []string) (location, detail string, collided bool) {
	switch node := value.(type) {
	case map[string]any:
		if at, why, found := TwinNames(node, tokens); found {
			return at, why, true
		}
		for _, name := range SortedNames(node) {
			if at, why, found := DataCollision(node[name], Child(tokens, name)); found {
				return at, why, true
			}
		}
	case []any:
		for index, item := range node {
			if at, why, found := DataCollision(item, Child(tokens, Index(index))); found {
				return at, why, true
			}
		}
	default:
		// A scalar carries no keys.
	}
	return "", "", false
}

// TwinNames reports the first pair of sibling keys sharing a canonical form.
// Keys are compared in sorted order so the reported pair is deterministic.
func TwinNames(declared map[string]any, tokens []string) (location, detail string, collided bool) {
	seen := make(map[string]string, len(declared))
	for _, name := range SortedNames(declared) {
		canonical := CanonicalKey(name)
		if other, taken := seen[canonical]; taken {
			at := FormatPointer(tokens)
			return at, fmt.Sprintf("keys %q and %q at %s share the canonical form %q", other, name, at, canonical), true
		}
		seen[canonical] = name
	}
	return "", "", false
}
