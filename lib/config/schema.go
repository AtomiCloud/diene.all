package config

import (
	"bytes"
	"encoding/json"
	"errors"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/invopop/jsonschema"
	tekuri "github.com/santhosh-tekuri/jsonschema/v6"
)

// Draft2020 is the JSON Schema draft this package generates and validates
// against.
const Draft2020 = "https://json-schema.org/draft/2020-12/schema"

// schemaResourceURL is the in-memory resource id the composed root schema is
// registered under before compilation. It never leaves the process.
const schemaResourceURL = "https://diene.atomi.cloud/config/root.schema.json"

// Block is one composable section of the root configuration schema. Engines
// export the [Block] for the section they own — otel, auth-engine, api-engine,
// standard-config — and a service composes them with [ComposeSchema] alongside
// its own keys. config never defines an engine's block schema; it only merges
// and validates the fragments it is handed.
type Block struct {
	// Key is the root property the fragment is mounted under, e.g. "otel".
	Key string
	// Required marks the block as mandatory in the composed root schema.
	Required bool
	// Schema is the draft-2020-12 JSON Schema fragment describing the block.
	Schema map[string]any
}

// NewBlock builds a [Block] mounting fragment under key. It is the constructor
// engines use to export their owned section for composition.
func NewBlock(key string, required bool, fragment map[string]any) Block {
	return Block{Key: key, Required: required, Schema: fragment}
}

// Schema is a composed, validatable root configuration schema.
type Schema struct {
	root   map[string]any
	portal problem.ErrorPortal
}

// ComposeSchema assembles a draft-2020-12 root object schema from block
// fragments. Each block becomes a property under its key; required blocks join
// the root "required" list. Additional top-level keys are permitted so a
// service can carry its own configuration alongside the composed engine blocks.
// Later blocks with the same key win, mirroring layer-merge precedence.
func ComposeSchema(blocks ...Block) Schema {
	properties := make(map[string]any, len(blocks))
	required := make([]any, 0, len(blocks))
	for _, block := range blocks {
		properties[block.Key] = block.Schema
		if block.Required {
			required = append(required, block.Key)
		}
	}
	root := map[string]any{
		"$schema":              Draft2020,
		"type":                 "object",
		"properties":           properties,
		"additionalProperties": true,
	}
	if len(required) > 0 {
		root["required"] = required
	}
	return Schema{root: root}
}

// Root returns the composed root schema as a JSON-like map. The returned map is
// the schema this [Schema] validates against and is what [Schema.Marshal]
// serializes for the committed artifact.
func (s Schema) Root() map[string]any {
	return s.root
}

// Marshal renders the composed root schema as indented draft-2020-12 JSON — the
// form committed as the generated schema artifact.
func (s Schema) Marshal() ([]byte, error) {
	return json.MarshalIndent(s.root, "", "  ")
}

// GenerateSchema reflects a Go type into a draft-2020-12 JSON Schema fragment
// using invopop/jsonschema. It is the generator engines and services use to
// derive a [Block] fragment from a typed model, and the artifact generator uses
// to emit the committed schema.
func GenerateSchema(model any) ([]byte, error) {
	reflector := &jsonschema.Reflector{
		Anonymous:                 true,
		DoNotReference:            true,
		ExpandedStruct:            true,
		AllowAdditionalProperties: true,
	}
	return json.MarshalIndent(reflector.Reflect(model), "", "  ")
}

// FragmentFromType reflects a Go type into a JSON Schema fragment map suitable
// for [NewBlock]. It threads the reflection and decode through a single error
// path so a caller composes typed blocks without hand-authoring JSON.
func FragmentFromType(model any) (map[string]any, error) {
	raw, marshalErr := GenerateSchema(model)
	fragment := map[string]any{}
	return fragment, errors.Join(marshalErr, json.Unmarshal(raw, &fragment))
}

// SchemaFromJSON loads a composed root schema from its committed JSON artifact,
// so a service can validate against the exact schema it ships rather than
// recomposing it at runtime.
func SchemaFromJSON(raw []byte) (Schema, error) {
	root := map[string]any{}
	if err := json.Unmarshal(raw, &root); err != nil {
		return Schema{}, err
	}
	return Schema{root: root}, nil
}

// compile marshals the composed root schema and compiles it with
// santhosh-tekuri/jsonschema. A malformed block fragment surfaces here rather
// than at validation time.
func (s Schema) compile() (*tekuri.Schema, error) {
	raw, marshalErr := json.Marshal(s.root)
	document, decodeErr := tekuri.UnmarshalJSON(bytes.NewReader(raw))
	compiler := tekuri.NewCompiler()
	addErr := compiler.AddResource(schemaResourceURL, document)
	if joined := errors.Join(marshalErr, decodeErr, addErr); joined != nil {
		return nil, joined
	}
	return compiler.Compile(schemaResourceURL)
}
