package schemaview

import (
	"fmt"
	"strings"
)

// RootPointer is the reference naming a resource root itself.
const RootPointer = "#"

// PointerPrefix introduces a local RFC-6901 JSON Pointer reference.
const PointerPrefix = "#/"

// ParsePointer decodes a local reference into its RFC-6901 tokens. Exactly two
// forms are supported: "#", which yields no tokens, and "#/..."; anything with a
// scheme, an authority, an anchor name, percent encoding, or a malformed escape
// is rejected here as an authoring fault rather than handed to the compiler.
func ParsePointer(reference string) ([]string, error) {
	if strings.ContainsRune(reference, '%') {
		return nil, fmt.Errorf("reference %q uses percent encoding, which is not supported", reference)
	}
	if reference == RootPointer {
		return []string{}, nil
	}
	rest, isLocal := strings.CutPrefix(reference, PointerPrefix)
	if !isLocal {
		return nil, fmt.Errorf("reference %q is not a local %q or %q pointer", reference, RootPointer, PointerPrefix)
	}
	tokens := []string{}
	for encoded := range strings.SplitSeq(rest, "/") {
		token, err := UnescapeToken(encoded)
		if err != nil {
			return nil, fmt.Errorf("reference %q: %w", reference, err)
		}
		tokens = append(tokens, token)
	}
	return tokens, nil
}

// UnescapeToken decodes one RFC-6901 token, requiring every "~" to introduce a
// valid "~0" or "~1" escape.
func UnescapeToken(encoded string) (string, error) {
	if !strings.ContainsRune(encoded, '~') {
		return encoded, nil
	}
	var builder strings.Builder
	builder.Grow(len(encoded))
	index := 0
	for index < len(encoded) {
		if encoded[index] != '~' {
			builder.WriteByte(encoded[index])
			index++
			continue
		}
		if index+1 >= len(encoded) {
			return "", fmt.Errorf("token %q ends with a dangling %q escape", encoded, "~")
		}
		switch encoded[index+1] {
		case '0':
			builder.WriteByte('~')
		case '1':
			builder.WriteByte('/')
		default:
			return "", fmt.Errorf("token %q contains the malformed escape %q", encoded, encoded[index:index+2])
		}
		index += 2
	}
	return builder.String(), nil
}

// EscapeToken encodes one RFC-6901 token, escaping "~" before "/" so the two
// replacements cannot interfere.
func EscapeToken(token string) string {
	return strings.ReplaceAll(strings.ReplaceAll(token, "~", "~0"), "/", "~1")
}

// FormatPointer renders tokens as a local reference, escaping each token.
func FormatPointer(tokens []string) string {
	if len(tokens) == 0 {
		return RootPointer
	}
	escaped := make([]string, 0, len(tokens))
	for _, token := range tokens {
		escaped = append(escaped, EscapeToken(token))
	}
	return PointerPrefix + strings.Join(escaped, "/")
}

// Child returns a fresh token path extending tokens with token, so a walk can
// descend without aliasing its parent's slice.
func Child(tokens []string, token string) []string {
	child := make([]string, 0, len(tokens)+1)
	child = append(child, tokens...)
	return append(child, token)
}

// EqualTokens reports whether two token paths are identical.
func EqualTokens(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

// CanonicalizePointerTokens rewrites the tokens of a reference so it still
// resolves after schema canonicalization: a token is canonicalized exactly when
// the container it indexes is a name-bearing map, which is precisely when the
// preceding token is one of the name-bearing keywords. Every other token — a
// "$defs" entry name, a keyword, an array index — is left alone.
func CanonicalizePointerTokens(tokens []string) []string {
	rewritten := make([]string, 0, len(tokens))
	for index, token := range tokens {
		if index > 0 && IsNameBearingKeyword(tokens[index-1]) {
			rewritten = append(rewritten, CanonicalKey(token))
			continue
		}
		rewritten = append(rewritten, token)
	}
	return rewritten
}
