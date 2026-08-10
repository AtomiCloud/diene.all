package coreutils_test

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper"
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

func TestStableHash(t *testing.T) {
	t.Parallel()
	first, errorValue := coreutils.StableHash(map[string]any{"a": 1, "b": 2})
	if errorValue != nil {
		t.Fatal(errorValue)
	}
	second, errorValue := coreutils.StableHash(map[string]any{"b": 2, "a": 1})
	if errorValue != nil || first != second {
		t.Fatalf("StableHash key order not stable: %q vs %q (%v)", first, second, errorValue)
	}
	if other, _ := coreutils.StableHash(map[string]any{"a": 1}); other == first {
		t.Fatal("distinct values hashed identically")
	}
	if _, errorValue := coreutils.StableHash(make(chan int)); errorValue == nil {
		t.Fatal("unencodable value accepted")
	}
}

func TestFileAndClockSeams(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	filesystem := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	if errorValue := filesystem.WriteText(ctx, "/greeting.txt", "hello", interfaces.WriteOptions{CreateParents: true}); errorValue != nil {
		t.Fatal(errorValue)
	}
	digest, errorValue := coreutils.HashFile(ctx, filesystem, "/greeting.txt")
	if errorValue != nil || digest != "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" {
		t.Fatalf("HashFile = %q, %v", digest, errorValue)
	}
	if _, errorValue = coreutils.HashFile(ctx, filesystem, "/missing.txt"); errorValue == nil {
		t.Fatal("missing file accepted")
	}

	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	system.SetNow(time.Date(2026, 7, 21, 1, 2, 3, 456000000, time.UTC))
	instant, errorValue := coreutils.NowWireInstant(system)
	if errorValue != nil || instant != "2026-07-21T01:02:03.456Z" {
		t.Fatalf("NowWireInstant = %q, %v", instant, errorValue)
	}
	system.EnqueueClockResult(time.Time{}, errors.New("clock unavailable"))
	if _, errorValue = coreutils.NowWireInstant(system); errorValue == nil {
		t.Fatal("clock error not propagated")
	}
	system.SetNow(time.Date(10000, 1, 1, 0, 0, 0, 0, time.UTC))
	if _, errorValue = coreutils.NowWireInstant(system); errorValue == nil {
		t.Fatal("out of range instant accepted")
	}
}

func TestMapConcurrent(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	doubled, errorValue := coreutils.MapConcurrent(ctx, []int{1, 2, 3, 4}, 2,
		func(_ context.Context, value int) (int, error) { return value * 2, nil })
	if errorValue != nil || !reflect.DeepEqual(doubled, []int{2, 4, 6, 8}) {
		t.Fatalf("MapConcurrent = %v, %v", doubled, errorValue)
	}
	empty, errorValue := coreutils.MapConcurrent(ctx, []int{}, 0,
		func(_ context.Context, value int) (int, error) { return value, nil })
	if errorValue != nil || len(empty) != 0 {
		t.Fatalf("empty MapConcurrent = %v, %v", empty, errorValue)
	}
	failing := errors.New("boom")
	_, errorValue = coreutils.MapConcurrent(ctx, []int{1, 2, 3}, 1,
		func(_ context.Context, value int) (int, error) {
			if value == 1 {
				return 0, failing
			}
			return value, nil
		})
	if !errors.Is(errorValue, failing) {
		t.Fatalf("first error not returned: %v", errorValue)
	}
}

func TestMapConcurrentParentCancellation(t *testing.T) {
	t.Parallel()
	parent, cancel := context.WithCancel(context.Background())
	started := make(chan struct{})
	release := make(chan struct{})
	type outcome struct {
		values []int
		err    error
	}
	done := make(chan outcome, 1)
	go func() {
		values, err := coreutils.MapConcurrent(parent, []int{0, 1}, 1,
			func(_ context.Context, value int) (int, error) {
				if value == 0 {
					close(started)
					<-release
				}
				return value, nil
			})
		done <- outcome{values, err}
	}()
	<-started
	cancel()
	close(release)
	got := <-done
	if !errors.Is(got.err, context.Canceled) || got.values != nil {
		t.Fatalf("cancelled MapConcurrent = %v, %v", got.values, got.err)
	}
}

func assertValidationProblem(t *testing.T, errorValue error, field string) {
	t.Helper()
	var typed *problem.Error
	if !errors.As(errorValue, &typed) || typed.Problem.Status != 400 || typed.Problem.Data["fields"].([]any)[0].(map[string]any)["path"] != field {
		t.Fatalf("error %v is not the expected validation problem for %s", errorValue, field)
	}
}
