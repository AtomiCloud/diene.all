package coreutils

import "strings"

// DeepClone returns an independent clone of a JSON-like value.
func DeepClone(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		clone := make(map[string]any, len(typed))
		for key, item := range typed {
			clone[key] = DeepClone(item)
		}
		return clone
	case []any:
		clone := make([]any, len(typed))
		for index, item := range typed {
			clone[index] = DeepClone(item)
		}
		return clone
	default:
		return value
	}
}

// DeepMerge immutably overlays overlay onto base. Nested maps merge while
// scalars and lists replace; map keys match across snake, kebab, camel, and
// Pascal spellings.
func DeepMerge(base map[string]any, overlay map[string]any) map[string]any {
	result := make(map[string]any, len(base))
	for key, value := range base {
		result[key] = DeepClone(value)
	}
	existing := make(map[string]string, len(result))
	for key := range result {
		existing[CanonicalConfigKey(key)] = key
	}
	for key, incoming := range overlay {
		canonical := CanonicalConfigKey(key)
		target, found := existing[canonical]
		if !found {
			target = key
		}
		currentMap, currentOK := result[target].(map[string]any)
		incomingMap, incomingOK := incoming.(map[string]any)
		if currentOK && incomingOK {
			result[target] = DeepMerge(currentMap, incomingMap)
		} else {
			result[target] = DeepClone(incoming)
		}
		existing[canonical] = target
	}
	return result
}

// DeepMergeAll merges layers in declaration order.
func DeepMergeAll(layers ...map[string]any) map[string]any {
	result := map[string]any{}
	for _, layer := range layers {
		result = DeepMerge(result, layer)
	}
	return result
}

// CanonicalConfigKey removes separators and lowercases a configuration key.
func CanonicalConfigKey(key string) string {
	return strings.ToLower(strings.NewReplacer("-", "", "_", "").Replace(key))
}

// ConfigKeysMatch reports whether two configuration keys identify one logical key.
func ConfigKeysMatch(left string, right string) bool {
	return CanonicalConfigKey(left) == CanonicalConfigKey(right)
}
