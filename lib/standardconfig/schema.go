package standardconfig

// keyedSchema wraps an entry fragment as a keyed map of named connections.
//
// This is the ONE shape every infra preset takes: a JSON object whose
// additionalProperties is the entry schema, so adding a named instance is a
// YAML edit and never a schema change. The key SPELLING is intentionally
// unconstrained here — see [ValidKey] for why the UPPERCASE contract lives in
// Go instead.
func keyedSchema(description string, entry map[string]any) map[string]any {
	return map[string]any{
		"type":                 "object",
		"description":          description,
		"additionalProperties": entry,
	}
}

// hostSchema declares a required, non-blank hostname.
func hostSchema(description string) map[string]any {
	return map[string]any{
		"type":        "string",
		"minLength":   1,
		"description": description,
	}
}

// portSchema declares a TCP port in the valid range.
func portSchema(description string) map[string]any {
	return map[string]any{
		"type":        "integer",
		"minimum":     1,
		"maximum":     65535,
		"description": description,
	}
}

// secretSchema declares a secret string: blank in YAML, injected per landscape
// through the environment override tier (R14, M33).
//
// It carries no minLength on purpose. The committed YAML holds a blank
// placeholder in every landscape, and a blank environment value is unset, so
// requiring a non-empty value here would make the base document invalid
// against its own schema.
func secretSchema(description string) map[string]any {
	return map[string]any{
		"type":        "string",
		"description": description + " Secret: blank in YAML, injected per landscape (R14/M33).",
	}
}

// boolSchema declares a boolean flag.
func boolSchema(description string) map[string]any {
	return map[string]any{
		"type":        "boolean",
		"description": description,
	}
}

// nonBlankSchema declares a required, non-blank string.
func nonBlankSchema(description string) map[string]any {
	return map[string]any{
		"type":        "string",
		"minLength":   1,
		"description": description,
	}
}

// countSchema declares a non-negative integer with an explicit floor.
func countSchema(minimum int, description string) map[string]any {
	return map[string]any{
		"type":        "integer",
		"minimum":     minimum,
		"description": description,
	}
}

// objectSchema declares a closed object with every listed property required.
//
// Every preset entry is closed and fully required: an infra block with a
// misspelled or missing key is a deployment that dials the wrong endpoint, so
// it fails schema validation at startup instead.
func objectSchema(description string, properties map[string]any) map[string]any {
	required := make([]any, 0, len(properties))
	for _, name := range Keys(properties) {
		required = append(required, name)
	}
	return map[string]any{
		"type":                 "object",
		"description":          description,
		"additionalProperties": false,
		"required":             required,
		"properties":           properties,
	}
}
