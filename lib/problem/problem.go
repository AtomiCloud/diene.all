package problem

import (
	"encoding/json"
	"strconv"
)

// UncataloguedProblemID is the id carried by an unexpected/uncatalogued problem
// (C0 §14 uncatalogued ⇒ 5xx ⇒ catalog-loop rule). It is used as the fallback
// id when no concrete registry entry is known.
const UncataloguedProblemID = "uncatalogued"

const (
	blankType              = "about:blank"
	unexpectedProblemTitle = "Unexpected problem"
	defaultProblemStatus   = 500
	defaultProblemVersion  = "v1"
)

// Problem is an RFC 9457 problem-details envelope plus the AtomiCloud `data`
// and `recoverable` extensions (C0 §2).
//
// The standard RFC 9457 members are Type, Title, Status, Detail, and Instance.
// The extensions are Data (the typed payload whose schema is published per
// problem in the catalog) and Recoverable (the flag the frontend classifier
// splits retry-vs-fatal on). Detail and Instance are optional: an empty string
// is treated as absent and omitted from the wire form.
//
// Type is always a URI minted by [TypeURI]; this type never formats the
// template itself.
type Problem struct {
	// Type is the RFC 9457 `type` URI identifying the problem type.
	Type string
	// Title is the RFC 9457 short, human-readable summary.
	Title string
	// Status is the RFC 9457 origin-generated HTTP status code.
	Status int
	// Detail is the RFC 9457 human-readable, occurrence-specific explanation.
	Detail string
	// Instance is the RFC 9457 URI identifying the specific occurrence.
	Instance string
	// Recoverable reports whether the frontend may offer a retry (C0 §2/§14).
	Recoverable bool
	// Data is the typed payload extension (schema published per problem).
	Data map[string]any
}

// MarshalJSON renders the envelope in its canonical wire shape
// (`type,title,status,detail?,instance?,recoverable,data`). Detail and Instance
// are omitted when empty; Data always renders as an object (never null).
func (p Problem) MarshalJSON() ([]byte, error) {
	out := map[string]any{
		"type":        p.Type,
		"title":       p.Title,
		"status":      p.Status,
		"recoverable": p.Recoverable,
		"data":        p.dataOrEmpty(),
	}
	if p.Detail != "" {
		out["detail"] = p.Detail
	}
	if p.Instance != "" {
		out["instance"] = p.Instance
	}
	return json.Marshal(out)
}

// UnmarshalJSON parses the envelope from its JSON object form, applying the
// RFC 9457 defaults for absent members (about:blank type, 500 status).
func (p *Problem) UnmarshalJSON(data []byte) error {
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	*p = problemFromMap(raw)
	return nil
}

// Equal reports whether p and other serialize to the same canonical JSON. It
// is value equality tolerant of int-vs-float numeric decoding across the wire.
func (p Problem) Equal(other Problem) bool {
	left := marshalProblem(p)
	right := marshalProblem(other)
	return left != "" && left == right
}

// String returns a compact human-readable form of the envelope.
func (p Problem) String() string {
	return "Problem(" + p.Type + ", " + strconv.Itoa(p.Status) + ", " + p.Title + ")"
}

func (p Problem) dataOrEmpty() map[string]any {
	if p.Data == nil {
		return map[string]any{}
	}
	return p.Data
}

func marshalProblem(p Problem) string {
	encoded, err := json.Marshal(p)
	if err != nil {
		return ""
	}
	return string(encoded)
}

func problemFromMap(raw map[string]any) Problem {
	return Problem{
		Type:        stringField(raw, "type", blankType),
		Title:       stringField(raw, "title", unexpectedProblemTitle),
		Status:      intField(raw, "status", defaultProblemStatus),
		Detail:      stringField(raw, "detail", ""),
		Instance:    stringField(raw, "instance", ""),
		Recoverable: boolField(raw, "recoverable"),
		Data:        dataField(raw, "data"),
	}
}

func stringField(raw map[string]any, key, fallback string) string {
	if value, ok := raw[key].(string); ok {
		return value
	}
	return fallback
}

func intField(raw map[string]any, key string, fallback int) int {
	if value, ok := raw[key].(float64); ok {
		return int(value)
	}
	return fallback
}

func boolField(raw map[string]any, key string) bool {
	value, ok := raw[key].(bool)
	return ok && value
}

func dataField(raw map[string]any, key string) map[string]any {
	if value, ok := raw[key].(map[string]any); ok {
		return value
	}
	return map[string]any{}
}
