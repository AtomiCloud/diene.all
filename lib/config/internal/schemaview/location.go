package schemaview

// AuthoredLocation maps a validator instance location, which is expressed over
// the canonical instance, back to the spellings the user actually wrote.
//
// Each segment is resolved against the ORIGINAL instance: inside a map the
// unique authored key whose canonical form matches is taken, and inside an array
// the segment is read as an index. Deciding by the current value's shape is what
// keeps a map key literally named "0" a key rather than an index. Sibling
// canonical twins are rejected before validation, so the map step is always
// unique. If the shape does not match — which the loader's own checks make
// unreachable, but a caller of the internal API could still reach — the
// remaining canonical segments are appended verbatim, so the location stays
// deterministic and nothing panics.
func AuthoredLocation(original any, canonical []string) []string {
	authored := make([]string, 0, len(canonical))
	current := original
	for index, segment := range canonical {
		switch node := current.(type) {
		case map[string]any:
			name, value, found := UniqueCanonicalKey(node, segment)
			if !found {
				return append(authored, canonical[index:]...)
			}
			authored = append(authored, name)
			current = value
		case []any:
			position, err := ParseIndex(segment)
			if err != nil || position >= len(node) {
				return append(authored, canonical[index:]...)
			}
			authored = append(authored, segment)
			current = node[position]
		default:
			return append(authored, canonical[index:]...)
		}
	}
	return authored
}

// UniqueCanonicalKey returns the single authored key of node whose canonical
// form is segment, together with its value. Keys are examined in sorted order,
// so even a document that somehow carries twins resolves deterministically.
func UniqueCanonicalKey(node map[string]any, segment string) (name string, value any, found bool) {
	for _, candidate := range SortedNames(node) {
		if CanonicalKey(candidate) == segment {
			return candidate, node[candidate], true
		}
	}
	return "", nil, false
}
