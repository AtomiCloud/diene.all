package domain_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestDomainProblemsRegistryCatalogAndRaise(t *testing.T) {
	t.Parallel()
	portal := samplePortal()
	extra := problem.Type{ID: "sample-extra", Title: "Sample extra", Version: "v1", Status: 409}
	problems, err := domain.NewProblems(portal, "consumer.messages", "v1", extra)
	if err != nil {
		t.Fatalf("construct problems: %v", err)
	}
	if _, found := problems.Registry().Lookup(domain.MessageHandlerFailedID); !found {
		t.Fatal("handler problem missing from registry")
	}
	entry, found := problems.Catalog().Lookup(domain.MessageHandlerFailedID)
	if !found || len(entry.Endpoints) != 1 || entry.Endpoints[0].Method != "CONSUME" ||
		entry.Endpoints[0].Path != "/streams/consumer.messages" {
		t.Fatalf("catalog entry = %#v", entry)
	}
	if _, found := problems.Catalog().Lookup(extra.ID); !found {
		t.Fatal("extra problem missing from catalog")
	}
	if len(problems.Catalog().ToCRDContent()) == 0 {
		t.Fatal("catalog CRD content is empty")
	}
	sentinel := errors.New("storage down")
	raised := problems.RaiseHandler("message-1", "storage", "message storage failed", sentinel)
	assertProblem(t, raised)
	if !errors.Is(raised, sentinel) {
		t.Fatalf("raised error does not preserve cause: %v", raised)
	}
	raised = problems.RaiseHandler("message-2", "persistence", "message persistence failed", nil)
	assertProblem(t, raised)
	if domain.MessageHandlerProblem("v2").Version != "v2" {
		t.Fatal("message handler problem did not retain requested version")
	}
}

func TestNewProblemsRejectsInvalidInput(t *testing.T) {
	t.Parallel()
	duplicate := domain.MessageHandlerProblem("v1")
	tests := []struct {
		name    string
		portal  problem.ErrorPortal
		stream  string
		version string
		extra   []problem.Type
	}{
		{name: "blank stream", portal: samplePortal(), stream: " ", version: "v1"},
		{name: "invalid version", portal: samplePortal(), stream: "messages", version: "one"},
		{name: "non-digit version", portal: samplePortal(), stream: "messages", version: "v1x"},
		{name: "duplicate type", portal: samplePortal(), stream: "messages", version: "v1", extra: []problem.Type{duplicate}},
		{name: "invalid portal", portal: problem.ErrorPortal{}, stream: "messages", version: "v1"},
		{name: "invalid extra version", portal: samplePortal(), stream: "messages", version: "v1", extra: []problem.Type{{ID: "extra", Title: "Extra", Version: "bad/version", Status: 500}}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := domain.NewProblems(test.portal, test.stream, test.version, test.extra...)
			assertProblem(t, err)
		})
	}
}

func samplePortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme: "https", Host: "errors.atomi.cloud", Landscape: "lapras",
		Platform: "diene", Service: "go-consumer", Module: "worker",
	}
}
