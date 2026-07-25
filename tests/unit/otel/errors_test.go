package otel_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestFaultConstructionAndNormalization(t *testing.T) {
	t.Parallel()

	portal := otel.Portal()
	if portal.Scheme != "https" || portal.Host != "docs.diene.atomicloud.com" ||
		portal.Landscape != "diene" || portal.Platform != "go" ||
		portal.Service != "otel" || portal.Module != "engine" {
		t.Fatalf("unexpected portal %#v", portal)
	}
	ids := []string{
		otel.FaultConfigInvalid,
		otel.FaultEndpointInvalid,
		otel.FaultDurationInvalid,
		otel.FaultSamplerInvalid,
		otel.FaultIdentityInvalid,
		otel.FaultRecordInvalid,
		otel.FaultEmitFailed,
		otel.FaultFlushFailed,
		otel.FaultShutdownFailed,
		otel.FaultEnvironmentUnavailable,
	}
	for _, id := range ids {
		problemValue := otel.FaultProblem(id, "title", "detail", otel.FaultStatusInvalidInput)
		wantURI, err := problem.TypeURI(portal, otel.FaultVersion, id)
		if err != nil {
			t.Fatalf("build expected URI: %v", err)
		}
		if problemValue.Type != wantURI || problemValue.Title != "title" ||
			problemValue.Status != otel.FaultStatusInvalidInput || problemValue.Detail == nil ||
			*problemValue.Detail != "detail" || problemValue.Data["id"] != id {
			t.Errorf("unexpected fault problem %#v", problemValue)
		}
		assertProblemID(t, otel.NewFault(id, "title", "detail", otel.FaultStatusInvalidInput), id)
	}

	sentinel := errors.New("sentinel")
	wrapped := otel.WrapFault(otel.FaultEmitFailed, "emit", "failed", otel.FaultStatusUnavailable, sentinel)
	assertProblemID(t, wrapped, otel.FaultEmitFailed)
	if !errors.Is(wrapped, sentinel) {
		t.Fatal("wrapped fault lost cause")
	}
	normalized := otel.NormalizeFault(sentinel)
	if !errors.Is(normalized, sentinel) {
		t.Fatal("normalized fault lost cause")
	}
	var normalizedProblem *problem.Error
	if !errors.As(normalized, &normalizedProblem) {
		t.Fatal("normalized error is not problem typed")
	}
	if got := otel.NormalizeFault(wrapped); !errors.Is(got, wrapped) {
		t.Fatal("problem error must pass through unchanged")
	}
	if got := otel.NormalizeFault(nil); got != nil {
		t.Fatal("nil normalization must remain nil")
	}
}
