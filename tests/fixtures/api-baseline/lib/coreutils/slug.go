package coreutils

import (
	"strings"
	"unicode"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"golang.org/x/text/unicode/norm"
)

// Slugify normalizes input with NFKD and returns a lowercase ASCII kebab slug.
func Slugify(input string) string {
	var builder strings.Builder
	separator := true
	for _, value := range norm.NFKD.String(input) {
		if unicode.Is(unicode.Mn, value) {
			continue
		}
		if value >= 'A' && value <= 'Z' {
			value += 'a' - 'A'
		}
		if (value >= 'a' && value <= 'z') || (value >= '0' && value <= '9') {
			builder.WriteRune(value)
			separator = false
			continue
		}
		if !separator && builder.Len() > 0 {
			builder.WriteByte('-')
			separator = true
		}
	}
	return strings.TrimSuffix(builder.String(), "-")
}

// NamespacedKey builds a normalized namespace:key value. Invalid components
// return a problem-typed validation error.
func NamespacedKey(namespace string, key string) (string, error) {
	normalizedNamespace := Slugify(namespace)
	if normalizedNamespace == "" {
		return "", namespacedKeyValidationError("namespace", "must not be empty")
	}
	normalizedKey := Slugify(key)
	if normalizedKey == "" {
		return "", namespacedKeyValidationError("key", "must not be empty")
	}
	return normalizedNamespace + ":" + normalizedKey, nil
}

func namespacedKeyValidationError(field string, message string) error {
	validation := problem.ValidationError()
	typeURI, _ := problem.TypeURI(problem.LocalErrorPortal(), validation.Version, validation.ID)
	return problem.NewError(problem.Problem{
		Type:        typeURI,
		Title:       validation.Title,
		Status:      validation.Status,
		Recoverable: validation.Recoverable,
		Data: map[string]any{"fields": []any{map[string]any{
			"path": field, "message": message,
		}}},
	})
}
