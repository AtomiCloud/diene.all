package config

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Config is a fully merged and validated configuration tree. It is produced by
// [Loader.Load] and, for tests, by [NewConfig] over an already-merged map.
type Config struct {
	raw map[string]any
}

// NewConfig wraps an already-merged, already-validated configuration tree.
// [Loader.Load] uses it after validation; the testhelper uses it to mint a
// pre-validated stub without running the full loader.
func NewConfig(raw map[string]any) *Config {
	return &Config{raw: raw}
}

// Raw returns an independent clone of the merged configuration tree, so callers
// cannot mutate the config through the returned map.
func (c *Config) Raw() map[string]any {
	return coreutils.DeepClone(c.raw).(map[string]any)
}

// Decode decodes the subtree at a dotted key into target, matching keys across
// snake, kebab, camel, and Pascal spellings. It is the typed-slice serving
// surface: pass a pointer to a slice or struct and the validated values decode
// into it. A missing key is an error.
func (c *Config) Decode(key string, target any) error {
	value, found := c.lookup(key)
	if !found {
		return fmt.Errorf("config: key %q not found", key)
	}
	raw, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("config: encode subtree %q: %w", key, err)
	}
	return json.Unmarshal(raw, target)
}

// App decodes the service-tree [AppBlock] from the "app" key.
func (c *Config) App() (AppBlock, error) {
	var app AppBlock
	if err := c.Decode(AppKey, &app); err != nil {
		return AppBlock{}, err
	}
	return app, nil
}

// lookup walks a dotted key against the merged tree using casing-insensitive key
// matching.
func (c *Config) lookup(key string) (any, bool) {
	var current any = c.raw
	for _, segment := range strings.Split(key, ".") {
		node, ok := current.(map[string]any)
		if !ok {
			return nil, false
		}
		value, found := matchKey(node, segment)
		if !found {
			return nil, false
		}
		current = value
	}
	return current, true
}

// matchKey resolves segment against node, preferring an exact hit and falling
// back to canonical (separator- and case-insensitive) matching.
func matchKey(node map[string]any, segment string) (any, bool) {
	if value, ok := node[segment]; ok {
		return value, true
	}
	canonical := coreutils.CanonicalConfigKey(segment)
	for key, value := range node {
		if coreutils.CanonicalConfigKey(key) == canonical {
			return value, true
		}
	}
	return nil, false
}
