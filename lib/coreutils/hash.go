package coreutils

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
)

// StableHash returns the lowercase hex SHA-256 of the canonical JSON encoding
// of a JSON-like value. Object keys are emitted in sorted order, so values that
// differ only by map iteration order hash identically. Values that cannot be
// encoded as JSON (for example channels or functions) return an error.
func StableHash(value any) (string, error) {
	encoded, errorValue := json.Marshal(value)
	if errorValue != nil {
		return "", fmt.Errorf("stable hash: %w", errorValue)
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:]), nil
}
