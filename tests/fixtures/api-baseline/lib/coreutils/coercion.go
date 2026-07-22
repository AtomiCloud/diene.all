package coreutils

import (
	"fmt"
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

var (
	environmentIntegerPattern = regexp.MustCompile(`^[+-]?(?:0|[1-9][0-9]*)$`)
	environmentDecimalPattern = regexp.MustCompile(`^[+-]?(?:(?:0|[1-9][0-9]*)\.[0-9]+|(?:0|[1-9][0-9]*)[eE][+-]?[0-9]+|(?:0|[1-9][0-9]*)\.[0-9]+[eE][+-]?[0-9]+)$`)
	environmentIndexPattern   = regexp.MustCompile(`^(?:0|[1-9][0-9]*)$`)
)

// EnvironmentCoercionError reports an invalid or ambiguous environment path.
type EnvironmentCoercionError struct {
	// Key is the source environment key or its materialized path.
	Key string
	// Reason describes why the path is invalid.
	Reason string
}

// Error implements error.
func (errorValue *EnvironmentCoercionError) Error() string {
	return "environment coercion: " + errorValue.Key + " " + errorValue.Reason
}

// CoerceEnvironmentScalar converts a configuration scalar into nil, bool, an
// IEEE-754-safe integer, float64, or its original string. It is not a money or
// wire-decimal codec.
func CoerceEnvironmentScalar(value string) any {
	if value == "" {
		return nil
	}
	switch strings.ToLower(value) {
	case "true":
		return true
	case "false":
		return false
	}
	if environmentIntegerPattern.MatchString(value) {
		parsed, errorValue := strconv.ParseInt(value, 10, 64)
		if errorValue == nil && math.Abs(float64(parsed)) <= 9007199254740991 {
			return parsed
		}
		return value
	}
	if environmentDecimalPattern.MatchString(value) {
		parsed, errorValue := strconv.ParseFloat(value, 64)
		if errorValue == nil {
			return parsed
		}
	}
	return value
}

// EnvironmentToNestedMap converts prefixed environment values into a nested
// JSON-like map. Double underscores separate components and numeric components
// materialize contiguous zero-based lists.
func EnvironmentToNestedMap(environment map[string]string, prefix string) (map[string]any, error) {
	root := map[string]any{}
	keys := make([]string, 0, len(environment))
	for key := range environment {
		if strings.HasPrefix(key, prefix) {
			keys = append(keys, key)
		}
	}
	slices.Sort(keys)
	for _, key := range keys {
		if environment[key] == "" {
			continue
		}
		suffix := strings.TrimPrefix(key, prefix)
		path := strings.Split(suffix, "__")
		if suffix == "" || hasEmptyPathSegment(path) {
			return nil, &EnvironmentCoercionError{Key: key, Reason: "must contain non-empty __-separated path components"}
		}
		if errorValue := insertEnvironmentPath(root, path, CoerceEnvironmentScalar(environment[key]), key); errorValue != nil {
			return nil, errorValue
		}
	}
	result := make(map[string]any, len(root))
	for key, child := range root {
		value, errorValue := materializeEnvironmentCollections(child, "<root>__"+key)
		if errorValue != nil {
			return nil, errorValue
		}
		result[key] = value
	}
	return result, nil
}

func hasEmptyPathSegment(path []string) bool {
	return slices.Contains(path, "")
}

func insertEnvironmentPath(root map[string]any, path []string, value any, sourceKey string) error {
	cursor := root
	for _, segment := range path[:len(path)-1] {
		normalized := strings.ToLower(segment)
		child, exists := cursor[normalized]
		if !exists {
			created := map[string]any{}
			cursor[normalized] = created
			cursor = created
			continue
		}
		next, ok := child.(map[string]any)
		if !ok {
			return &EnvironmentCoercionError{Key: sourceKey, Reason: "collides with a scalar configuration path"}
		}
		cursor = next
	}
	leaf := strings.ToLower(path[len(path)-1])
	if _, exists := cursor[leaf]; exists {
		return &EnvironmentCoercionError{Key: sourceKey, Reason: "duplicates a normalized configuration path"}
	}
	cursor[leaf] = value
	return nil
}

func materializeEnvironmentCollections(value any, path string) (any, error) {
	mapValue, ok := value.(map[string]any)
	if !ok {
		return DeepClone(value), nil
	}
	hasIndex := false
	for key := range mapValue {
		if environmentIndexPattern.MatchString(key) {
			hasIndex = true
			break
		}
	}
	if hasIndex {
		indexes := make([]int, 0, len(mapValue))
		for key := range mapValue {
			if !environmentIndexPattern.MatchString(key) {
				return nil, &EnvironmentCoercionError{Key: path, Reason: "mixes indexed and named child keys"}
			}
			parsed, _ := strconv.Atoi(key)
			indexes = append(indexes, parsed)
		}
		slices.Sort(indexes)
		result := make([]any, len(indexes))
		for expected, index := range indexes {
			if index != expected {
				return nil, &EnvironmentCoercionError{Key: path, Reason: fmt.Sprintf("uses sparse list indexes; expected %d", expected)}
			}
			child, errorValue := materializeEnvironmentCollections(mapValue[strconv.Itoa(index)], path+"__"+strconv.Itoa(index))
			if errorValue != nil {
				return nil, errorValue
			}
			result[index] = child
		}
		return result, nil
	}
	result := make(map[string]any, len(mapValue))
	for key, child := range mapValue {
		materialized, errorValue := materializeEnvironmentCollections(child, path+"__"+key)
		if errorValue != nil {
			return nil, errorValue
		}
		result[key] = materialized
	}
	return result, nil
}
