// Package layers builds and resolves the YAML configuration layers: it parses
// documents with two Viper instances, folds the overlay onto the base with
// MergeConfigMap after aligning cross-spelled keys canonically, resolves and
// validates the landscape token, and safely resolves a file-mode overlay path.
// It is an internal package with an exported, black-box-testable API, not part
// of the public config surface.
package layers

import (
	"bytes"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/tree"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/spf13/viper"
)

// appLandscapeKey is the dotted key the landscape is read from when it is not
// supplied explicitly.
const appLandscapeKey = "app.landscape"

// landscapeToken is the narrow ASCII grammar a landscape must match: a
// non-empty run of letters, digits, underscores, and hyphens. It admits no
// separators or dot segments, so it cannot express a path traversal.
var landscapeToken = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

// NewViper returns a Viper seeded with the tin loader shape: YAML config type
// and an env-key replacer. The env layer itself is produced by core-utils, not
// Viper AutomaticEnv, so the replacer is only part of the inherited seed shape.
func NewViper() *viper.Viper {
	instance := viper.New()
	instance.SetConfigType("yaml")
	instance.SetEnvKeyReplacer(strings.NewReplacer("-", "_", ".", "__"))
	return instance
}

// BaseViper parses the base document into its own Viper instance. A nil document
// yields an empty configuration.
func BaseViper(content []byte) (*viper.Viper, error) {
	instance := NewViper()
	if err := instance.ReadConfig(bytes.NewReader(content)); err != nil {
		return nil, err
	}
	return instance, nil
}

// MergeOverlay parses the overlay into a second Viper instance and folds it onto
// base with MergeConfigMap. It first aligns the overlay's keys onto the base's
// canonical spellings via [AlignKeys], so a cross-spelled overlay value
// overrides the base key it matches instead of coexisting with a duplicate.
func MergeOverlay(base *viper.Viper, content []byte) error {
	overlay := NewViper()
	if err := overlay.ReadConfig(bytes.NewReader(content)); err != nil {
		return err
	}
	return base.MergeConfigMap(AlignKeys(base.AllSettings(), overlay.AllSettings()))
}

// AlignKeys rewrites overlay's keys to base's spelling wherever they identify
// the same logical key under the core-utils canonical rule, recursing into
// nested maps. Keys absent from base keep their overlay spelling.
func AlignKeys(base, overlay map[string]any) map[string]any {
	index := make(map[string]string, len(base))
	for key := range base {
		index[coreutils.CanonicalConfigKey(key)] = key
	}
	aligned := make(map[string]any, len(overlay))
	for key, value := range overlay {
		target := key
		if baseKey, ok := index[coreutils.CanonicalConfigKey(key)]; ok {
			target = baseKey
			baseChild, baseOK := base[baseKey].(map[string]any)
			overlayChild, overlayOK := value.(map[string]any)
			if baseOK && overlayOK {
				value = AlignKeys(baseChild, overlayChild)
			}
		}
		aligned[target] = value
	}
	return aligned
}

// ResolveLandscape returns the explicit landscape when set, otherwise the base
// document's app.landscape, or the empty string when neither is present.
func ResolveLandscape(base map[string]any, explicit string) string {
	if explicit != "" {
		return explicit
	}
	value, ok := tree.Lookup(base, appLandscapeKey)
	if !ok {
		return ""
	}
	landscape, ok := value.(string)
	if !ok {
		return ""
	}
	return landscape
}

// ValidateLandscape enforces the landscape token grammar, rejecting empty
// tokens, separators, and dot segments before any path is built.
func ValidateLandscape(landscape string) error {
	if !landscapeToken.MatchString(landscape) {
		return fmt.Errorf("landscape %q must be a non-empty token of ASCII letters, digits, underscores, and hyphens", landscape)
	}
	return nil
}

// OverlayPath resolves the file-mode overlay path settings.<landscape>.yaml
// under dir. It enforces the landscape token grammar itself and, as defence in
// depth, verifies with filepath.Rel that the joined path still resolves to that
// exact filename directly inside dir; a grammar or containment failure returns
// one error. It is the single safe entry point for file-mode landscape
// resolution, so the traversal rejection is exercised through this path.
func OverlayPath(dir, landscape string) (string, error) {
	name := "settings." + landscape + ".yaml"
	path := filepath.Join(dir, name)
	relative, relErr := filepath.Rel(dir, path)
	if ValidateLandscape(landscape) != nil || relErr != nil || relative != name {
		return "", fmt.Errorf("landscape %q must be a safe in-directory token", landscape)
	}
	return path, nil
}
