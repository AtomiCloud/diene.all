package otelsdk

import (
	"math"

	"go.opentelemetry.io/otel/attribute"
)

// Attributes converts portable telemetry attributes into OpenTelemetry
// attributes. Integer widths are widened to int64 and float32 to float64, which
// is the SDK's own attribute domain. A value outside the convertible domain is
// skipped: otel.ValidAttributeValue already rejected it before conversion is
// attempted, so this is a defence in depth rather than a silent policy.
//
// Only the v1-stable attribute package appears here. The v0 logs types stay
// contained inside the logs sink so this module's public surface never depends on
// a pre-1.0 module.
func Attributes(attributes map[string]any) []attribute.KeyValue {
	converted := make([]attribute.KeyValue, 0, len(attributes))
	for name, value := range attributes {
		if keyValue, ok := Attribute(name, value); ok {
			converted = append(converted, keyValue)
		}
	}
	return converted
}

// Attribute converts one portable attribute, reporting whether the value has an
// OpenTelemetry representation.
//
// Unsigned integers are rejected above [math.MaxInt64]: the attribute domain is
// signed 64-bit, so a larger value has no faithful representation and silently
// wrapping it would emit a negative number for a positive measurement.
func Attribute(name string, value any) (attribute.KeyValue, bool) {
	switch typed := value.(type) {
	case bool:
		return attribute.Bool(name, typed), true
	case string:
		return attribute.String(name, typed), true
	case int:
		return attribute.Int64(name, int64(typed)), true
	case int8:
		return attribute.Int64(name, int64(typed)), true
	case int16:
		return attribute.Int64(name, int64(typed)), true
	case int32:
		return attribute.Int64(name, int64(typed)), true
	case int64:
		return attribute.Int64(name, typed), true
	case uint:
		if uint64(typed) > math.MaxInt64 {
			return attribute.KeyValue{}, false
		}
		return attribute.Int64(name, int64(uint64(typed))), true
	case uint8:
		return attribute.Int64(name, int64(typed)), true
	case uint16:
		return attribute.Int64(name, int64(typed)), true
	case uint32:
		return attribute.Int64(name, int64(typed)), true
	case uint64:
		if typed > math.MaxInt64 {
			return attribute.KeyValue{}, false
		}
		return attribute.Int64(name, int64(typed)), true
	case float32:
		return attribute.Float64(name, float64(typed)), true
	case float64:
		return attribute.Float64(name, typed), true
	case []bool:
		return attribute.BoolSlice(name, typed), true
	case []string:
		return attribute.StringSlice(name, typed), true
	case []int:
		return attribute.IntSlice(name, typed), true
	case []int64:
		return attribute.Int64Slice(name, typed), true
	case []float64:
		return attribute.Float64Slice(name, typed), true
	default:
		return attribute.KeyValue{}, false
	}
}

// RepresentableUnsigned reports whether an unsigned value fits the signed 64-bit
// attribute domain without wrapping.
func RepresentableUnsigned(value uint64) bool { return value <= math.MaxInt64 }
