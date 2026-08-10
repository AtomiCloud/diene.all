package standardconfig

// PresetNames returns the frozen infra preset keys in stable order.
//
// The set is closed by C0 §3: postgres, cache, kv, storage. A fifth infra
// preset is a contract change agreed across bun, dotnet, and go, never a local
// addition.
func PresetNames() []string {
	return []string{CacheBlockKey, KvBlockKey, PostgresBlockKey, StorageBlockKey}
}

// Schemas returns every shipped preset fragment keyed by its frozen block key.
//
// A service that composes all four writes one loop instead of four calls; a
// service that needs two calls the two constructors directly.
func Schemas() map[string]map[string]any {
	return map[string]map[string]any{
		CacheBlockKey:    CacheSchema(),
		KvBlockKey:       KvSchema(),
		PostgresBlockKey: PostgresSchema(),
		StorageBlockKey:  StorageSchema(),
	}
}

// SchemaFor returns the fragment for one preset by its block key.
//
// An unknown key is a problem-typed error listing the shipped presets rather
// than a nil fragment, because a nil fragment composed into a root schema
// silently stops constraining anything.
func SchemaFor(problems *Problems, blockKey string) (map[string]any, error) {
	schema, found := Schemas()[blockKey]
	if found {
		return schema, nil
	}
	if problems == nil {
		return nil, errUnconfigured()
	}
	return nil, problems.Raise(ProblemPresetUnknown,
		"this library ships no infra preset under that key",
		map[string]any{"key": blockKey, "shipped": PresetNames()})
}
