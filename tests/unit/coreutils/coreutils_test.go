package coreutils_test

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestSlugifyAndNamespacedKey(t *testing.T) {
	t.Parallel()
	for input, want := range map[string]string{"Hello World": "hello-world", "mañana": "manana", "  Résumé café  ": "resume-cafe", "!!!": ""} {
		if got := coreutils.Slugify(input); got != want {
			t.Fatalf("Slugify(%q) = %q, want %q", input, got, want)
		}
	}
	key, errorValue := coreutils.NamespacedKey("Diene Go", "Core Utils")
	if errorValue != nil || key != "diene-go:core-utils" {
		t.Fatalf("NamespacedKey() = %q, %v", key, errorValue)
	}
	_, errorValue = coreutils.NamespacedKey("!!!", "key")
	assertValidationProblem(t, errorValue, "namespace")
	_, errorValue = coreutils.NamespacedKey("namespace", "!!!")
	assertValidationProblem(t, errorValue, "key")
}

func TestMerge(t *testing.T) {
	t.Parallel()
	base := map[string]any{"auth": map[string]any{"clientId": "base", "scopes": []any{"openid"}}, "enabled": false}
	overlay := map[string]any{"AUTH": map[string]any{"client_id": "overlay", "scopes": []any{"openid", "offline_access"}}, "enabled": true}
	got := coreutils.DeepMerge(base, overlay)
	want := map[string]any{"auth": map[string]any{"clientId": "overlay", "scopes": []any{"openid", "offline_access"}}, "enabled": true}
	enabled, ok := base["enabled"].(bool)
	if !reflect.DeepEqual(got, want) || !ok || enabled {
		t.Fatalf("DeepMerge() = %#v; base = %#v", got, base)
	}
	cloneValue := coreutils.DeepClone(map[string]any{"items": []any{"value"}})
	clone, ok := cloneValue.(map[string]any)
	if !ok {
		t.Fatalf("DeepClone() = %#v, want map", cloneValue)
	}
	clone["items"].([]any)[0] = "changed"
	if coreutils.DeepMergeAll(map[string]any{"value": 1}, map[string]any{"value": 2})["value"] != 2 || !coreutils.ConfigKeysMatch("client-id", "clientId") || coreutils.ConfigKeysMatch("one", "two") || coreutils.CanonicalConfigKey("Error_Portal") != "errorportal" {
		t.Fatal("configuration merge helpers did not preserve their contract")
	}
}

func TestEnvironmentCoercion(t *testing.T) {
	t.Parallel()
	got, errorValue := coreutils.EnvironmentToNestedMap(map[string]string{
		"ATOMI_AUTH__ENABLED": "true", "ATOMI_AUTH__RETRIES": "3", "ATOMI_AUTH__RATIO": "0.25", "ATOMI_AUTH__SCOPES__0": "openid", "ATOMI_AUTH__SCOPES__1": "offline_access", "ATOMI_AUTH__EMPTY": "", "OTHER": "ignored",
	}, "ATOMI_")
	want := map[string]any{"auth": map[string]any{"enabled": true, "retries": int64(3), "ratio": 0.25, "scopes": []any{"openid", "offline_access"}}}
	if errorValue != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("EnvironmentToNestedMap() = %#v, %v", got, errorValue)
	}
	for _, value := range []string{"", "false", "9007199254740992", "one,two", "1e3"} {
		_ = coreutils.CoerceEnvironmentScalar(value)
	}
	for _, environment := range []map[string]string{{"ATOMI_": "value"}, {"ATOMI_A____B": "value"}, {"ATOMI_A": "value", "ATOMI_A__B": "value"}, {"ATOMI_A": "value", "ATOMI_a": "value"}, {"ATOMI_A__0": "value", "ATOMI_A__NAME": "value"}, {"ATOMI_A__1": "value"}, {"ATOMI_A__0__0": "value", "ATOMI_A__0__NAME": "value"}, {"ATOMI_A__B__0__0": "value", "ATOMI_A__B__0__NAME": "value"}} {
		_, errorValue = coreutils.EnvironmentToNestedMap(environment, "ATOMI_")
		var coercion *coreutils.EnvironmentCoercionError
		if !errors.As(errorValue, &coercion) {
			t.Fatalf("EnvironmentToNestedMap(%v) error = %v, want coercion error", environment, errorValue)
		}
		_ = coercion.Error()
	}
}

func TestC0TemporalConformance(t *testing.T) {
	t.Parallel()
	codec := coreutils.WireCodec{}
	if coreutils.C0Temporal.Provenance.IANARelease != coreutils.IANATimeZoneRelease || coreutils.C0Temporal.DigestPayload() == "" {
		t.Fatal("C0 temporal provenance is not pinned")
	}
	for _, value := range coreutils.C0Temporal.Dates.Valid {
		parsed, errorValue := codec.DecodeDate(value)
		if errorValue != nil || codec.EncodeDate(parsed) != value {
			t.Fatalf("date %q did not round-trip: %v", value, errorValue)
		}
	}
	for _, value := range coreutils.C0Temporal.Dates.Invalid {
		if _, errorValue := codec.DecodeDate(value); errorValue == nil {
			t.Fatalf("invalid date %q was accepted", value)
		}
	}
	for _, value := range coreutils.C0Temporal.Times.Valid {
		parsed, errorValue := codec.DecodeTime(value)
		if errorValue != nil || codec.EncodeTime(parsed) != value {
			t.Fatalf("time %q did not round-trip: %v", value, errorValue)
		}
	}
	for _, value := range coreutils.C0Temporal.Times.Invalid {
		if _, errorValue := codec.DecodeTime(value); errorValue == nil {
			t.Fatalf("invalid time %q was accepted", value)
		}
	}
	for _, vector := range coreutils.C0Temporal.Instants {
		input, errorValue := time.Parse(time.RFC3339Nano, vector.Input)
		if errorValue != nil {
			t.Fatal(errorValue)
		}
		got, errorValue := codec.EncodeInstant(input)
		if errorValue != nil || got != vector.CanonicalUTC {
			t.Fatalf("instant %q = %q, %v", vector.Input, got, errorValue)
		}
		if _, errorValue = codec.DecodeInstant(vector.CanonicalUTC); errorValue != nil {
			t.Fatal(errorValue)
		}
	}
	for _, value := range coreutils.C0Temporal.InvalidInstants {
		if _, errorValue := codec.DecodeInstant(value); errorValue == nil {
			t.Fatalf("invalid instant %q was accepted", value)
		}
	}
	for _, value := range coreutils.C0Temporal.Durations.Valid {
		parsed, errorValue := codec.DecodeDuration(value)
		if errorValue != nil || codec.EncodeDuration(parsed) == "" {
			t.Fatalf("duration %q did not round-trip: %v", value, errorValue)
		}
	}
	for _, value := range coreutils.C0Temporal.Durations.Invalid {
		if _, errorValue := codec.DecodeDuration(value); errorValue == nil {
			t.Fatalf("invalid duration %q was accepted", value)
		}
	}
	for _, value := range coreutils.C0Temporal.Timezones.Valid {
		parsed, errorValue := codec.DecodeTimezone(value)
		if !coreutils.IsIanaTimezone(value) || errorValue != nil || codec.EncodeTimezone(parsed) != value {
			t.Fatalf("timezone %q did not round-trip: %v", value, errorValue)
		}
	}
	for _, value := range coreutils.C0Temporal.Timezones.Invalid {
		if coreutils.IsIanaTimezone(value) {
			t.Fatalf("invalid timezone %q was accepted", value)
		}
		if _, errorValue := codec.DecodeTimezone(value); errorValue == nil {
			t.Fatalf("invalid timezone %q decoded", value)
		}
	}
}

func TestWireConstructorsAndSleep(t *testing.T) {
	t.Parallel()
	if _, errorValue := coreutils.NewWireDate(2026, 2, 30); errorValue == nil {
		t.Fatal("invalid date accepted")
	}
	if _, errorValue := coreutils.FormatRFC3339UTC(time.Date(10000, 1, 1, 0, 0, 0, 0, time.UTC)); errorValue == nil {
		t.Fatal("out of range instant accepted")
	}
	if _, errorValue := coreutils.NewWireTime(1, 60, 1); errorValue == nil {
		t.Fatal("invalid time accepted")
	}
	if value, errorValue := coreutils.ParseIsoDuration("PT0,5S"); errorValue != nil || value.String() != "PT0.5S" {
		t.Fatalf("duration = %s, %v", value, errorValue)
	}
	if errorValue := coreutils.Sleep(context.Background(), -time.Nanosecond); errorValue == nil {
		t.Fatal("negative sleep accepted")
	}
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	if errorValue := coreutils.Sleep(cancelled, time.Hour); !errors.Is(errorValue, context.Canceled) {
		t.Fatalf("cancelled sleep = %v", errorValue)
	}
	if errorValue := coreutils.Sleep(context.Background(), 0); errorValue != nil {
		t.Fatal(errorValue)
	}
}

func assertValidationProblem(t *testing.T, errorValue error, field string) {
	t.Helper()
	var typed *problem.Error
	if !errors.As(errorValue, &typed) || typed.Problem.Status != 400 || typed.Problem.Data["fields"].([]any)[0].(map[string]any)["path"] != field {
		t.Fatalf("error %v is not the expected validation problem for %s", errorValue, field)
	}
}
