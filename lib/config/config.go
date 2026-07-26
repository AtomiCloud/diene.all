package config

import (
	"encoding/json"
	"fmt"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/clone"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/tree"
)

// Config is a fully merged and validated configuration tree. It is produced by
// [Loader.Load] and, for tests, by [NewConfig] over an already-merged map.
type Config struct {
	raw map[string]any
}

// NewConfig wraps an already-merged configuration tree. It deep-clones raw over
// the supported configuration domain — string-keyed maps, slices, arrays,
// pointers, and value-semantic structs (such as time.Time) — so the config owns
// an independent copy and later caller mutation cannot alter it or race a
// concurrent [Config.Decode]. A mutable value reachable only through a struct's
// unexported field is the one documented exception: reflection cannot copy it,
// so it stays shared (the JSON-like configuration domain has no such value).
// [Loader.Load] uses it after validation.
func NewConfig(raw map[string]any) *Config {
	return &Config{raw: clone.Map(raw)}
}

// Raw returns an independent deep clone of the merged configuration tree over the
// supported configuration domain (see [NewConfig]), so callers cannot mutate the
// config through the returned map.
func (c *Config) Raw() map[string]any {
	return clone.Map(c.raw)
}

// Decode decodes the subtree at a dotted key into target, matching keys across
// snake, kebab, camel, and Pascal spellings. It is the typed-slice serving
// surface: pass a pointer to a slice or struct and the validated values decode
// into it. A missing key, or a key whose canonical form is ambiguous among
// siblings, is an error, so resolution never depends on map iteration order.
func (c *Config) Decode(key string, target any) error {
	value, found := tree.Lookup(c.raw, key)
	if !found {
		return fmt.Errorf("config: key %q not found or ambiguous", key)
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
