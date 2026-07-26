package preview_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/preview"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	interfacesth "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// errBoom is the arbitrary seam failure the system mock is made to return.
var errBoom = errors.New("boom")

// requireProblems builds the harness problem factory or fails the test.
func requireProblems(t *testing.T) *e2e.Problems {
	t.Helper()
	problems, err := e2e.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	return problems
}

// completeEnvironment is a fully specified Garden preview environment.
func completeEnvironment() map[string]string {
	return map[string]string{
		preview.EnvPlatform:     "sulfoxide",
		preview.EnvService:      "billing",
		preview.EnvModule:       "core",
		preview.EnvVersion:      "1.4.2",
		preview.EnvBaseURL:      "https://billing.garden.atomi.cloud",
		preview.EnvOtlpEndpoint: "http://alloy.garden.atomi.cloud:4318",
		preview.EnvIssuer:       "https://logto.garden.atomi.cloud/oidc",
		preview.EnvAudience:     "https://billing.garden.atomi.cloud",
		preview.EnvJWKSURI:      "https://logto.garden.atomi.cloud/oidc/jwks",
	}
}

// systemWith builds the deterministic environment seam.
func systemWith(environment map[string]string) *interfacesth.InMemorySystem {
	return interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{Environment: environment})
}

// resolveComplete resolves a fully specified target or fails the test.
func resolveComplete(t *testing.T, mutate func(map[string]string)) preview.Target {
	t.Helper()
	environment := completeEnvironment()
	if mutate != nil {
		mutate(environment)
	}
	target, err := preview.Resolve(systemWith(environment), requireProblems(t))
	if err != nil {
		t.Fatalf("Resolve() error = %v", err)
	}
	return target
}

// problemID extracts the trailing id segment of a problem type URI.
func problemID(t *testing.T, err error) string {
	t.Helper()
	if err == nil {
		t.Fatal("expected a problem-typed error, got nil")
	}
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("expected a problem-typed error, got %v", err)
	}
	index := strings.LastIndex(typed.Problem.Type, "/")
	return typed.Problem.Type[index+1:]
}

// problemData extracts the `data` extension of a problem-typed error.
func problemData(t *testing.T, err error) map[string]any {
	t.Helper()
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("expected a problem-typed error, got %v", err)
	}
	return typed.Problem.Data
}
