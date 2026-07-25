package config

import (
	"encoding/json"
	"fmt"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/tree"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Config is a fully merged and validated configuration tree. It is produced by
// [Loader.Load] and, for tests, by [NewConfig] over an already-merged map.
type Config struct {
	raw map[string]any
}

// NewConfig wraps an already-merged configuration tree. It clones raw so the
// config owns an independent copy and later caller mutation cannot alter it or
// race a concurrent [Config.Decode]. [Loader.Load] uses it after validation.
func NewConfig(raw map[string]any) *Config {
	clone := make(map[string]any, len(raw))
	for key, value := range raw {
		clone[key] = coreutils.DeepClone(value)
	}
	return &Config{raw: clone}
}

// Raw returns an independent clone of the merged configuration tree, so callers
// cannot mutate the config through the returned map.
func (c *Config) Raw() map[string]any {
	clone := make(map[string]any, len(c.raw))
	for key, value := range c.raw {
		clone[key] = coreutils.DeepClone(value)
	}
	return clone
}

// Decode decodes the subtree at a dotted key into target, matching keys across
// snake, kebab, camel, and Pascal spellings. It is the typed-slice serving
// surface: pass a pointer to a slice or struct and the validated values decode
// into it. A missing key is an error.
func (c *Config) Decode(key string, target any) error {
	value, found := tree.Lookup(c.raw, key)
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
