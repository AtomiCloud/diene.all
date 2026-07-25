package otel_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

func assertProblemID(t *testing.T, err error, id string) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected problem %q, got nil", id)
	}
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		t.Fatalf("expected problem error %q, got %T: %v", id, err, err)
	}
	got, ok := problemErr.Problem.Data["id"].(string)
	if !ok || got != id {
		t.Fatalf("expected problem id %q, got %#v", id, problemErr.Problem.Data["id"])
	}
}

func systemWith(environment map[string]string) *interfaceshelper.InMemorySystem {
	return interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{
		Environment: environment,
	})
}
