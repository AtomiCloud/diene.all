// Package derive builds stable external names from fleet coordinates.
//
// It is deliberately a small pure primitive. Controllers supply the vendor
// profile that defines normalization and the name-length budget; controller
// specific DNS, delivery, and resource derivations do not belong here.
package derive

import (
	"crypto/sha256"
	"encoding/base32"
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"
)

// LPSM is the complete landscape, platform, service, and module coordinate.
// Every field participates in a derived name.
type LPSM struct {
	Landscape string
	Platform  string
	Service   string
	Module    string
}

// Coordinate is an alias for LPSM for callers that use the longer name.
type Coordinate = LPSM

// NormalizeFunc converts one raw coordinate segment into the charset accepted
// by a caller's external system. It must return a non-blank, valid UTF-8 value.
type NormalizeFunc func(string) (string, error)

// OverflowPolicy declares what happens when a complete readable name exceeds
// Profile.MaxLength. It is intentionally explicit: shortening is never an
// implicit side effect of name derivation.
type OverflowPolicy string

const (
	maxDigestLength = 52 // unpadded base32 encoding length of a SHA-256 digest

	// OverflowReject returns ErrNameTooLong instead of shortening a name.
	OverflowReject OverflowPolicy = "reject"
	// OverflowTrim keeps a deterministic prefix and the mandatory digest suffix.
	OverflowTrim OverflowPolicy = "trim-with-digest"
)

// Profile is the caller-owned normalization and length contract for one vendor
// name class. Lengths are UTF-8 byte budgets, which matches external API name
// limits. DigestLength is the number of lower-case base32 SHA-256 characters to
// retain (one character carries five bits of collision resistance).
type Profile struct {
	MaxLength    int
	Separator    string
	DigestLength int
	Overflow     OverflowPolicy
	Normalize    NormalizeFunc
}

// ErrorKind identifies a validation failure. It can be used with errors.Is.
type ErrorKind string

const (
	ErrInvalidProfile    ErrorKind = "derive: invalid profile"
	ErrBlankSegment      ErrorKind = "derive: blank segment"
	ErrUnnormalizable    ErrorKind = "derive: unnormalizable segment"
	ErrNameTooLong       ErrorKind = "derive: name exceeds length budget"
	ErrInvalidGeneration ErrorKind = "derive: invalid generation"
)

// Error gives callers typed context while preserving errors.Is support for an
// ErrorKind and for a normalizer's underlying error.
type Error struct {
	Kind  ErrorKind
	Field string
	Limit int
	Cause error
}

func (kind ErrorKind) Error() string { return string(kind) }

func (err *Error) Error() string {
	message := string(err.Kind)
	if err.Field != "" {
		message += fmt.Sprintf(" (%s)", err.Field)
	}
	if err.Limit != 0 {
		message += fmt.Sprintf(" (limit %d)", err.Limit)
	}
	if err.Cause != nil {
		message += ": " + err.Cause.Error()
	}
	return message
}

// Is lets callers match an ErrorKind with errors.Is.
func (err *Error) Is(target error) bool {
	kind, ok := target.(ErrorKind)
	return ok && err.Kind == kind
}

// Unwrap exposes a normalizer failure when one caused this error.
func (err *Error) Unwrap() error { return err.Cause }

// Validate checks that the complete output, including one readable byte, the
// separator, and the collision digest, can fit within the declared budget.
func (profile Profile) Validate() error {
	switch {
	case profile.MaxLength <= 0:
		return &Error{Kind: ErrInvalidProfile, Field: "max length"}
	case strings.TrimSpace(profile.Separator) == "":
		return &Error{Kind: ErrInvalidProfile, Field: "separator"}
	case profile.DigestLength <= 0 || profile.DigestLength > maxDigestLength:
		return &Error{Kind: ErrInvalidProfile, Field: "digest length"}
	case profile.Overflow != OverflowReject && profile.Overflow != OverflowTrim:
		return &Error{Kind: ErrInvalidProfile, Field: "overflow policy"}
	case profile.Normalize == nil:
		return &Error{Kind: ErrInvalidProfile, Field: "normalizer"}
	case profile.MaxLength <= len(profile.Separator)+profile.DigestLength:
		return &Error{Kind: ErrInvalidProfile, Field: "max length", Limit: profile.MaxLength}
	default:
		return nil
	}
}

// Name deterministically derives an external name from a full LPSM coordinate.
func Name(coordinate LPSM, profile Profile) (string, error) {
	return derive(profile, []segment{
		{field: "landscape", value: coordinate.Landscape},
		{field: "platform", value: coordinate.Platform},
		{field: "service", value: coordinate.Service},
		{field: "module", value: coordinate.Module},
	})
}

// ForkName deterministically derives the Garden fork variant of an LPSM name.
// Generation is non-negative so generation zero remains available to callers
// whose durable counter begins at zero.
func ForkName(coordinate LPSM, instance string, generation int64, profile Profile) (string, error) {
	if generation < 0 {
		return "", &Error{Kind: ErrInvalidGeneration, Field: "generation"}
	}
	return derive(profile, []segment{
		{field: "landscape", value: coordinate.Landscape},
		{field: "platform", value: coordinate.Platform},
		{field: "service", value: coordinate.Service},
		{field: "module", value: coordinate.Module},
		{field: "fork", value: "fork"},
		{field: "instance", value: instance},
		{field: "generation", value: strconv.FormatInt(generation, 10)},
	})
}

type segment struct {
	field string
	value string
}

func derive(profile Profile, segments []segment) (string, error) {
	if err := profile.Validate(); err != nil {
		return "", err
	}

	normalized := make([]string, 0, len(segments))
	for _, item := range segments {
		value, err := normalize(profile, item)
		if err != nil {
			return "", err
		}
		normalized = append(normalized, value)
	}

	body := strings.Join(normalized, profile.Separator)
	digest := digestFor(segments, profile.DigestLength)
	name := body + profile.Separator + digest
	if len(name) <= profile.MaxLength {
		return name, nil
	}
	if profile.Overflow == OverflowReject {
		return "", &Error{Kind: ErrNameTooLong, Limit: profile.MaxLength}
	}
	room := profile.MaxLength - len(profile.Separator) - len(digest)
	return prefixBytes(body, room) + profile.Separator + digest, nil
}

func normalize(profile Profile, item segment) (string, error) {
	if strings.TrimSpace(item.value) == "" {
		return "", &Error{Kind: ErrBlankSegment, Field: item.field}
	}
	normalized, err := profile.Normalize(item.value)
	if err != nil {
		return "", &Error{Kind: ErrUnnormalizable, Field: item.field, Cause: err}
	}
	if strings.TrimSpace(normalized) == "" || !utf8.ValidString(normalized) {
		return "", &Error{Kind: ErrUnnormalizable, Field: item.field}
	}
	return normalized, nil
}

func digestFor(segments []segment, length int) string {
	var preimage strings.Builder
	preimage.WriteString("derive/v1")
	for _, item := range segments {
		fmt.Fprintf(&preimage, "|%s:%d:%s", item.field, len(item.value), item.value)
	}
	sum := sha256.Sum256([]byte(preimage.String()))
	encoded := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(sum[:])
	return strings.ToLower(encoded[:length])
}

func prefixBytes(value string, limit int) string {
	for limit > 0 && !utf8.ValidString(value[:limit]) {
		limit--
	}
	return value[:limit]
}
