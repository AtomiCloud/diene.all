package otel

// SchemaKey returns the frozen root key services compose this block under.
func SchemaKey() string { return BlockKey }

// SamplerEnum returns the sampler vocabulary as JSON Schema enum members.
func SamplerEnum() []any {
	members := make([]any, 0, len(SamplerTypes()))
	for _, candidate := range SamplerTypes() {
		members = append(members, string(candidate))
	}
	return members
}

// DurationSchema returns the schema of one ISO 8601 duration field, described by
// what the duration controls.
func DurationSchema(description string) map[string]any {
	return map[string]any{
		"type":        "string",
		"description": "ISO 8601 duration: " + description,
	}
}

// ExporterSchema returns the exporter sub-schema shared by all three signals.
// Exporter selection is per-exporter booleans, never an enum string (C0 §4).
func ExporterSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"required":             []any{"console", "otlp"},
		"properties": map[string]any{
			"console": map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"required":             []any{"enabled"},
				"properties": map[string]any{
					"enabled": map[string]any{"type": "boolean"},
				},
			},
			"otlp": map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"required":             []any{"enabled", "endpoint", "protocol", "headers", "timeout"},
				"properties": map[string]any{
					"enabled": map[string]any{"type": "boolean"},
					"endpoint": map[string]any{
						"type": "string",
						"description": "OTLP collector base URL on port " + OtlpHTTPPort +
							"; empty when the exporter is off",
					},
					"protocol": map[string]any{
						"type": "string",
						"enum": []any{ProtocolHTTPProtobuf},
					},
					"headers": map[string]any{
						"type":                 "object",
						"additionalProperties": map[string]any{"type": "string"},
					},
					"timeout": DurationSchema("per-export timeout"),
				},
			},
		},
	}
}

// SamplerSchema returns the trace sampler sub-schema.
func SamplerSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"required":             []any{"type", "ratio"},
		"properties": map[string]any{
			"type":  map[string]any{"type": "string", "enum": SamplerEnum()},
			"ratio": map[string]any{"type": "number", "minimum": 0, "maximum": 1},
		},
	}
}

// JSONSchema returns the engine-owned JSON Schema for the canonical telemetry
// block (C0 §3: each engine library exports its OWN block schema next to the
// code that reads it).
//
// Services compose their root schema by importing this one object; the config
// library remains the sole merger and validator. Every object closes
// additionalProperties so an unknown or misspelled key fails validation at
// startup instead of being silently ignored.
func JSONSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"required":             []any{"logs", "metrics", "traces"},
		"properties": map[string]any{
			"logs": map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"required":             []any{"enabled", "exporter"},
				"properties": map[string]any{
					"enabled":  map[string]any{"type": "boolean"},
					"exporter": ExporterSchema(),
				},
			},
			"metrics": map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"required":             []any{"enabled", "exporter", "interval"},
				"properties": map[string]any{
					"enabled":  map[string]any{"type": "boolean"},
					"exporter": ExporterSchema(),
					"interval": DurationSchema("metric export interval"),
				},
			},
			"traces": map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"required":             []any{"enabled", "sampler", "exporter"},
				"properties": map[string]any{
					"enabled":  map[string]any{"type": "boolean"},
					"exporter": ExporterSchema(),
					"sampler":  SamplerSchema(),
				},
			},
		},
	}
}
