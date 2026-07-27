package problem

import (
	"encoding/json"
	"errors"
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
// splits retry-vs-fatal on). Detail and Instance are optional Go `*string`
// values mirroring RFC 9457's (and the Dart sibling's) nullable members: a nil
// pointer is absent and omitted from the wire form, while a non-nil pointer —
// including a pointer to an empty string — is present and emitted. This keeps a
// wire envelope with `"detail":""`/`"instance":""` losslessly round-trippable.
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
	// It is optional: nil is omitted from the wire form, a non-nil pointer
	// (including a pointer to an empty string) is emitted.
	Detail *string
	// Instance is the RFC 9457 URI identifying the specific occurrence. It is
	// optional with the same nil-omitted / present-emitted semantics as Detail.
	Instance *string
	// Recoverable reports whether the frontend may offer a retry (C0 §2/§14).
	Recoverable bool
	// Data is the typed payload extension (schema published per problem).
	Data map[string]any
}

// MarshalJSON renders the envelope in its canonical wire shape
// (`type,title,status,detail?,instance?,recoverable,data`). Detail and Instance
// are omitted when nil and emitted (even for an empty string) when non-nil;
// Data always renders as an object (never null).
func (p Problem) MarshalJSON() ([]byte, error) {
	data := p.Data
	if data == nil {
		data = map[string]any{}
	}
	out := map[string]any{
		"type":        p.Type,
		"title":       p.Title,
		"status":      p.Status,
		"recoverable": p.Recoverable,
		"data":        data,
	}
	if p.Detail != nil {
		out["detail"] = *p.Detail
	}
	if p.Instance != nil {
		out["instance"] = *p.Instance
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
	if raw == nil {
		return errors.New("problem must be a JSON object")
	}

	problemType := blankType
	if value, ok := raw["type"].(string); ok {
		problemType = value
	}
	title := unexpectedProblemTitle
	if value, ok := raw["title"].(string); ok {
		title = value
	}
	status := defaultProblemStatus
	if value, ok := raw["status"].(float64); ok {
		status = int(value)
	}
	var detail *string
	if value, ok := raw["detail"].(string); ok {
		detail = &value
	}
	var instance *string
	if value, ok := raw["instance"].(string); ok {
		instance = &value
	}
	recoverable := false
	if value, ok := raw["recoverable"].(bool); ok {
		recoverable = value
	}
	problemData, ok := raw["data"].(map[string]any)
	if !ok {
		problemData = map[string]any{}
	}
	*p = Problem{
		Type:        problemType,
		Title:       title,
		Status:      status,
		Detail:      detail,
		Instance:    instance,
		Recoverable: recoverable,
		Data:        problemData,
	}
	return nil
}

// Equal reports whether p and other serialize to the same canonical JSON. It
// is value equality tolerant of int-vs-float numeric decoding across the wire.
func (p Problem) Equal(other Problem) bool {
	left, leftErr := json.Marshal(p)
	right, rightErr := json.Marshal(other)
	return leftErr == nil && rightErr == nil && string(left) == string(right)
}

// String returns a compact human-readable form of the envelope.
func (p Problem) String() string {
	return "Problem(" + p.Type + ", " + strconv.Itoa(p.Status) + ", " + p.Title + ")"
}
