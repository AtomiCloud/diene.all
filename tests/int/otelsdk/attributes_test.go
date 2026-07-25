package otelsdk_test

import (
	"math"
	"testing"

	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"go.opentelemetry.io/otel/attribute"
)

func TestAttributeConversions(t *testing.T) {
	t.Parallel()

	tests := []struct {
		value  any
		typeOf attribute.Type
	}{
		{value: true, typeOf: attribute.BOOL},
		{value: "text", typeOf: attribute.STRING},
		{value: int(1), typeOf: attribute.INT64},
		{value: int8(1), typeOf: attribute.INT64},
		{value: int16(1), typeOf: attribute.INT64},
		{value: int32(1), typeOf: attribute.INT64},
		{value: int64(1), typeOf: attribute.INT64},
		{value: uint(1), typeOf: attribute.INT64},
		{value: uint8(1), typeOf: attribute.INT64},
		{value: uint16(1), typeOf: attribute.INT64},
		{value: uint32(1), typeOf: attribute.INT64},
		{value: uint64(1), typeOf: attribute.INT64},
		{value: float32(1.5), typeOf: attribute.FLOAT64},
		{value: float64(2.5), typeOf: attribute.FLOAT64},
		{value: []bool{true}, typeOf: attribute.BOOLSLICE},
		{value: []string{"one"}, typeOf: attribute.STRINGSLICE},
		{value: []int{1}, typeOf: attribute.INT64SLICE},
		{value: []int64{1}, typeOf: attribute.INT64SLICE},
		{value: []float64{1.5}, typeOf: attribute.FLOAT64SLICE},
	}
	for _, test := range tests {
		converted, ok := otelsdk.Attribute("key", test.value)
		if !ok || converted.Value.Type() != test.typeOf {
			t.Errorf("conversion of %#v: got %#v, %t", test.value, converted, ok)
		}
	}
	for _, value := range []any{uint64(math.MaxInt64) + 1, uint(math.MaxInt64) + 1, struct{}{}} {
		if _, ok := otelsdk.Attribute("key", value); ok {
			t.Errorf("unexpected conversion of %#v", value)
		}
	}
	converted := otelsdk.Attributes(map[string]any{
		"valid":   true,
		"invalid": struct{}{},
	})
	if len(converted) != 1 || string(converted[0].Key) != "valid" {
		t.Fatalf("unexpected converted set %#v", converted)
	}
	if !otelsdk.RepresentableUnsigned(math.MaxInt64) || otelsdk.RepresentableUnsigned(uint64(math.MaxInt64)+1) {
		t.Fatal("unsigned representability mismatch")
	}
}

func TestInstrumentKey(t *testing.T) {
	t.Parallel()

	if got := otelsdk.InstrumentKey("requests", "1"); got != "requests\x001" {
		t.Fatalf("unexpected instrument key %q", got)
	}
}
