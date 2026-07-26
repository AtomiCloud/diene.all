package config

// AppKey is the root property that carries the service-tree [AppBlock].
const AppKey = "app"

// AppBlock is the service-tree identity block every Diene service declares
// under the "app" key. Its landscape segment is the natural source of the
// runtime landscape when one is not passed explicitly to the loader, and the
// full LPSM tuple mirrors the service-tree identity used across the platform.
type AppBlock struct {
	// Landscape is the deployment landscape, e.g. lapras or pichu.
	Landscape string `json:"landscape" yaml:"landscape" jsonschema:"required"`
	// Platform is the owning platform segment.
	Platform string `json:"platform" yaml:"platform" jsonschema:"required"`
	// Service is the service segment.
	Service string `json:"service" yaml:"service" jsonschema:"required"`
	// Module is the module segment within the service.
	Module string `json:"module" yaml:"module" jsonschema:"required"`
	// Version is the released service version.
	Version string `json:"version" yaml:"version" jsonschema:"required"`
}

// AppBlockSchema returns the config-owned JSON Schema fragment for the "app"
// block. Unlike engine blocks, the service-tree identity block belongs to
// config itself, so it ships a stable literal fragment (draft 2020-12) rather
// than accepting one. GenerateSchema reflects the same [AppBlock] type and the
// oracle test proves the two agree.
func AppBlockSchema() Block {
	return NewBlock(AppKey, true, map[string]any{
		"type": "object",
		"properties": map[string]any{
			"landscape": map[string]any{"type": "string", "minLength": float64(1)},
			"platform":  map[string]any{"type": "string", "minLength": float64(1)},
			"service":   map[string]any{"type": "string", "minLength": float64(1)},
			"module":    map[string]any{"type": "string", "minLength": float64(1)},
			"version":   map[string]any{"type": "string", "minLength": float64(1)},
		},
		"required":             []any{"landscape", "platform", "service", "module", "version"},
		"additionalProperties": false,
	})
}
