package config

import (
	"context"
	"errors"
	"io/fs"
	"maps"
	"os"
	"strings"
)

// YAMLSource yields the raw YAML document of one configuration layer. The base
// layer and each landscape overlay are read through this seam so an in-memory
// fake can stand in for the filesystem in tests.
type YAMLSource interface {
	// Name identifies the layer for diagnostics.
	Name() string
	// Read returns the layer's YAML bytes. An absent optional layer returns
	// (nil, nil) rather than an error.
	Read(ctx context.Context) ([]byte, error)
}

// EnvSource yields the process environment folded on as the final layer.
type EnvSource interface {
	// Name identifies the layer for diagnostics.
	Name() string
	// Environ returns the environment as a flat key to value map.
	Environ(ctx context.Context) (map[string]string, error)
}

// BytesYAMLSource is a YAMLSource backed by an in-memory document. It is the
// source the testhelper and inline callers use to supply a base or overlay
// without touching the filesystem.
type BytesYAMLSource struct {
	name    string
	content []byte
}

// NewBytesYAMLSource creates an in-memory YAML layer named name. It clones
// content so later caller mutation cannot alter the layer; a nil document
// stays nil (an absent layer).
func NewBytesYAMLSource(name string, content []byte) BytesYAMLSource {
	return BytesYAMLSource{name: name, content: append([]byte(nil), content...)}
}

// Name returns the layer name.
func (s BytesYAMLSource) Name() string { return s.name }

// Read returns a clone of the in-memory document, so a caller cannot mutate the
// layer through the returned slice. A nil content yields an absent layer.
func (s BytesYAMLSource) Read(_ context.Context) ([]byte, error) {
	return append([]byte(nil), s.content...), nil
}

// FileYAMLSource is a YAMLSource backed by a filesystem path. A missing
// required file is an error; a missing optional file is an absent layer.
type FileYAMLSource struct {
	name     string
	path     string
	optional bool
}

// NewFileYAMLSource creates a required YAML layer read from path.
func NewFileYAMLSource(name, path string) FileYAMLSource {
	return FileYAMLSource{name: name, path: path}
}

// NewOptionalFileYAMLSource creates an optional YAML layer; a missing file
// yields an absent layer instead of an error, which is how a landscape with no
// overlay resolves.
func NewOptionalFileYAMLSource(name, path string) FileYAMLSource {
	return FileYAMLSource{name: name, path: path, optional: true}
}

// Name returns the layer name.
func (s FileYAMLSource) Name() string { return s.name }

// Path returns the filesystem path the layer reads from.
func (s FileYAMLSource) Path() string { return s.path }

// Read returns the file contents, or (nil, nil) when an optional file is
// absent.
func (s FileYAMLSource) Read(_ context.Context) ([]byte, error) {
	content, err := os.ReadFile(s.path)
	if err != nil {
		if s.optional && errors.Is(err, fs.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	return content, nil
}

// OSEnvSource reads the live process environment.
type OSEnvSource struct{}

// NewOSEnvSource creates a source over the live process environment.
func NewOSEnvSource() OSEnvSource { return OSEnvSource{} }

// Name returns the layer name.
func (OSEnvSource) Name() string { return "process-environment" }

// Environ returns the process environment as a flat map.
func (OSEnvSource) Environ(_ context.Context) (map[string]string, error) {
	entries := os.Environ()
	environment := make(map[string]string, len(entries))
	for _, entry := range entries {
		key, value, _ := strings.Cut(entry, "=")
		environment[key] = value
	}
	return environment, nil
}

// MapEnvSource is an EnvSource backed by an in-memory map, used to drive the
// env layer deterministically in tests.
type MapEnvSource struct {
	name string
	vars map[string]string
}

// NewMapEnvSource creates an in-memory env layer named name. It clones vars so
// later caller mutation cannot alter the layer.
func NewMapEnvSource(name string, vars map[string]string) MapEnvSource {
	clone := make(map[string]string, len(vars))
	maps.Copy(clone, vars)
	return MapEnvSource{name: name, vars: clone}
}

// Name returns the layer name.
func (s MapEnvSource) Name() string { return s.name }

// Environ returns a clone of the in-memory environment, so a caller cannot
// mutate the layer through the returned map.
func (s MapEnvSource) Environ(_ context.Context) (map[string]string, error) {
	clone := make(map[string]string, len(s.vars))
	maps.Copy(clone, s.vars)
	return clone, nil
}
