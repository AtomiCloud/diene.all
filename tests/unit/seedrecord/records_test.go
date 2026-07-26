package seedrecord_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-consumer/lib/seedrecord"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestParseAndSelectMissing(t *testing.T) {
	t.Parallel()
	records, err := seedrecord.Parse([]byte(`[
  {"id":" existing ","value":"one"},
  {"id":"missing","value":""}
]`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(records) != 2 || records[0].ID != "existing" || records[1].Value != "" {
		t.Fatalf("records = %#v", records)
	}
	missing := seedrecord.SelectMissing(records, map[string]struct{}{"existing": {}})
	if len(missing) != 1 || missing[0].ID != "missing" {
		t.Fatalf("missing = %#v", missing)
	}
	all := seedrecord.SelectMissing(records, nil)
	if len(all) != 2 {
		t.Fatalf("all missing = %#v", all)
	}
}

func TestParseAcceptsEmptyArray(t *testing.T) {
	t.Parallel()
	records, err := seedrecord.Parse([]byte(`[]`))
	if err != nil {
		t.Fatalf("parse empty array: %v", err)
	}
	if records == nil || len(records) != 0 {
		t.Fatalf("records = %#v, want non-nil empty slice", records)
	}
}

func TestParseRejectsInvalidSeedData(t *testing.T) {
	t.Parallel()
	tests := [][]byte{
		[]byte(`not-json`),
		[]byte(`[{"id":"one","value":"one","extra":true}]`),
		[]byte(`[{"id":"one","value":"one"}] {}`),
		[]byte(`null`),
		[]byte(`[{"id":" ","value":"one"}]`),
		[]byte(`[{"id":"one"}]`),
	}
	for _, input := range tests {
		_, err := seedrecord.Parse(input)
		assertProblem(t, err)
	}
}

func assertProblem(t *testing.T, err error) {
	t.Helper()
	if err == nil {
		t.Fatal("expected an error")
	}
	var carried *problem.Error
	if !errors.As(err, &carried) {
		t.Fatalf("error is not problem typed: %T %v", err, err)
	}
}
