// Package resource derives the schema resource identifier a composed
// configuration block is mounted under. Giving each block its own resource is
// what makes an independently authored fragment portable: a fragment-local
// "#/$defs/..." reference then resolves against the block, not the composed
// root, and cannot reach across blocks.
//
// The identifier must be a valid URI for an ARBITRARY block key, so the key is
// never interpolated raw. It is encoded with base64 raw URL encoding over the
// key's JSON-visible bytes, which keeps the mapping injective on exactly the
// keys a JSON document can distinguish and keeps compose-time and artifact-time
// derivation in agreement.
//
// It is an internal package with an exported, black-box-testable API, not part
// of the public config surface.
package resource

import (
	"encoding/base64"
	"strings"
	"unicode/utf8"
)

// Prefix is the fixed absolute-URI prefix every generated block resource shares.
const Prefix = "https://diene.atomi.cloud/config/blocks/"

// Suffix is the fixed extension every generated block resource ends with. It is
// outside the base64 raw URL alphabet, so it cannot collide with encoded bytes.
const Suffix = ".schema.json"

// BlockID returns the resource identifier for a block mounted under key. Two
// keys that a JSON document can tell apart always yield different identifiers,
// and every identifier is a valid absolute URI regardless of what the key
// contains — including slashes, dots, spaces, and non-ASCII text.
func BlockID(key string) string {
	return Prefix + base64.RawURLEncoding.EncodeToString([]byte(NormalizeJSONString(key))) + Suffix
}

// NormalizeJSONString returns text as it survives an encoding/json round trip:
// every byte that is not part of a valid UTF-8 sequence becomes U+FFFD, one
// replacement per offending byte. Deriving the identifier from this form is what
// keeps a compose-time lookup and a lookup against the marshalled artifact in
// agreement, since the artifact can only carry the normalized spelling.
func NormalizeJSONString(text string) string {
	if utf8.ValidString(text) {
		return text
	}
	var builder strings.Builder
	builder.Grow(len(text))
	index := 0
	for index < len(text) {
		decoded, size := utf8.DecodeRuneInString(text[index:])
		if decoded == utf8.RuneError && size == 1 {
			builder.WriteRune(utf8.RuneError)
			index++
			continue
		}
		builder.WriteString(text[index : index+size])
		index += size
	}
	return builder.String()
}
