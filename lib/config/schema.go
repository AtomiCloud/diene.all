package config

import (
	"encoding/json"
	"errors"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/clone"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/resource"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/valid"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/invopop/jsonschema"
)

// Draft2020 is the JSON Schema draft this package generates and validates
// against.
const Draft2020 = "https://json-schema.org/draft/2020-12/schema"

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
	//
	// The fragment is mounted as its own schema RESOURCE, so an ordinary
	// fragment-local pointer such as {"$ref": "#/$defs/body"} resolves inside the
	// block and stays portable; it cannot reach into another block. Do not author
	// "$id" or "$schema" here — [ComposeSchema] owns the composed root's dialect
	// and generates each block's resource identity.
	//
	// A supported SUBSET of the dialect is accepted, because validation matches
	// keys canonically (see [Schema.Validate]). Rejected as authoring faults:
	// patternProperties and propertyNames, which constrain the authored spelling
	// of a key; $anchor, $dynamicAnchor, $dynamicRef, $recursiveAnchor,
	// $recursiveRef, and any non-local, percent-encoded, or anchor-form $ref;
	// $vocabulary; dependencies and additionalItems, which the 2020-12 dialect
	// ignores; and contentSchema, contentEncoding, and contentMediaType, which
	// this validator does not assert. Those words appearing as DATA under const,
	// enum, default, examples, or an unknown annotation are ordinary content.
	Schema map[string]any
}

// NewBlock builds a [Block] mounting fragment under key. It clones fragment over
// the JSON-like schema domain (string-keyed maps, slices, and scalars) so the
// block owns an independent copy and later caller mutation cannot alter the
// composed schema. It is the constructor engines use to export their owned
// section for composition.
func NewBlock(key string, required bool, fragment map[string]any) Block {
	return Block{Key: key, Required: required, Schema: clone.Map(fragment)}
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
//
// Blocks are composed on the JSON-VISIBLE spelling of [Block.Key] — the spelling
// the key has once serialized, in which any byte that is not valid UTF-8 becomes
// U+FFFD. Two keys that a JSON document cannot tell apart are therefore ONE
// block, and the later block wins its fragment, its requiredness, and its
// generated resource identity, mirroring layer-merge precedence. [Block.Key]
// itself keeps whatever the caller supplied.
//
// Every block is mounted with a generated "$id", making it its own schema
// resource: a fragment-local "#/$defs/..." pointer resolves against the block
// rather than the composed root, which is what lets independently authored
// fragments use ordinary local pointers. A fragment that authors its own "$id"
// is left intact and rejected by [Schema.Validate], so the mistake is reported
// rather than silently overwritten.
func ComposeSchema(blocks ...Block) Schema {
	properties := make(map[string]any, len(blocks))
	requiredByKey := make(map[string]bool, len(blocks))
	order := make([]string, 0, len(blocks))
	for _, block := range blocks {
		// Compose on the JSON-VISIBLE spelling of the key. Two distinct Go strings
		// can serialize to one JSON member name (any byte that is not valid UTF-8
		// becomes U+FFFD), so indexing by the raw string would emit two members
		// that collapse on decode — and the survivor would be whichever raw key
		// sorted last, not the block supplied last. Deciding here keeps
		// later-wins precedence deterministic for the fragment, the requiredness,
		// and the generated resource identity alike. Block.Key itself is the
		// caller's value and is never rewritten.
		visibleKey := resource.NormalizeJSONString(block.Key)
		if _, seen := properties[visibleKey]; !seen {
			order = append(order, visibleKey)
		}
		// Each block is mounted as its own schema RESOURCE, so a fragment-local
		// "#/$defs/..." reference resolves against the block rather than the
		// composed root. That is what makes an independently authored fragment
		// portable, and it also means no reference can reach across blocks. An
		// authored "$id" is left untouched so the audit can reject it instead of
		// this silently overwriting the evidence.
		fragment := clone.Map(block.Schema)
		if fragment == nil {
			fragment = map[string]any{}
		}
		if _, authored := fragment["$id"]; !authored {
			fragment["$id"] = resource.BlockID(visibleKey)
		}
		properties[visibleKey] = fragment
		requiredByKey[visibleKey] = block.Required
	}
	required := make([]any, 0, len(order))
	for _, key := range order {
		if requiredByKey[key] {
			required = append(required, key)
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

// Root returns an independent clone of the composed root schema as a JSON-like
// map, so callers cannot mutate the schema this [Schema] validates against. It
// is the shape [Schema.Marshal] serializes for the committed artifact.
func (s Schema) Root() map[string]any {
	return clone.Map(s.root)
}

// Marshal renders the composed root schema as indented draft-2020-12 JSON — the
// form committed as the generated schema artifact.
func (s Schema) Marshal() ([]byte, error) {
	return json.MarshalIndent(s.root, "", "  ")
}

// WithPortal returns a copy of the schema whose validation failures mint their
// type URI from portal. A service passes its build-time service-tree portal so
// the problem type URI carries its own LPSM identity.
func (s Schema) WithPortal(portal problem.ErrorPortal) Schema {
	s.portal = portal
	return s
}

// Validate checks instance against the composed root schema exactly once.
//
// Keys match CANONICALLY: separators and case are ignored, exactly as
// [Config.Decode] resolves a dotted key. Both sides are put in canonical form
// before the compiler runs, so every key comparison it makes — properties,
// required, dependentRequired, additionalProperties fall-through, unevaluated
// accounting, the inner checks of not and contains, and object const and enum
// equality — is spelling-insensitive. A spelling Decode can resolve is therefore
// always a spelling this constrains. Two branches may spell one logical key
// differently; they name one key and each branch's constraints apply natively.
// Sibling keys that share a canonical form are rejected, since canonicalizing
// them would collapse two declarations into one.
//
// Reported paths carry the AUTHORED spellings of the instance; message text may
// name the canonical form of a property, so the path is the authoritative
// locator.
//
// A schema-validation failure is returned as a problem-typed *[problem.Error]
// (validation-error, HTTP 400, recoverable) carrying the offending field paths
// and messages under data.fields. An unsupported schema construct (see [Block]),
// a canonical collision, a malformed schema, or an instance that cannot be
// normalized is returned as a plain wrapped error, since those are authoring
// faults rather than configuration-validation failures.
func (s Schema) Validate(instance map[string]any) error {
	return valid.Evaluate(s.root, s.portal, instance)
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
//
// The reflector emits root resource markers ("$schema" and "$id") that describe
// a standalone document; a mountable fragment must not carry them, because
// [ComposeSchema] owns the composed root's dialect and generates each block's
// resource identity. Only those two reflector-generated root keys are removed —
// a hand-authored "$schema" or "$id" in a fragment remains an authoring fault.
func FragmentFromType(model any) (map[string]any, error) {
	raw, marshalErr := GenerateSchema(model)
	fragment := map[string]any{}
	err := errors.Join(marshalErr, json.Unmarshal(raw, &fragment))
	delete(fragment, "$schema")
	delete(fragment, "$id")
	return fragment, err
}
