package coreutils

import (
	"context"
	"crypto/sha256"
	"encoding/hex"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// HashFile reads path through the virtual filesystem seam and returns the
// lowercase hex SHA-256 of its bytes. Any read error is returned unwrapped so
// the caller keeps the seam's problem typing.
func HashFile(ctx context.Context, filesystem interfaces.Vfs, path string) (string, error) {
	content, errorValue := filesystem.ReadBytes(ctx, path)
	if errorValue != nil {
		return "", errorValue
	}
	digest := sha256.Sum256(content)
	return hex.EncodeToString(digest[:]), nil
}
