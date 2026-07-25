package otel_test

import (
	"errors"
	"maps"
	"testing"

	"github.com/AtomiCloud/diene.go-interfaces/testhelper"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestAppIdentityAndResourceAttributes(t *testing.T) {
	t.Parallel()

	identity := otel.AppIdentity{
		Landscape: " lapras ",
		Platform:  " platform ",
		Service:   " service ",
		Module:    " module ",
		Version:   " 1.2.3 ",
	}
	if err := identity.Validate(); err != nil {
		t.Fatalf("identity must validate: %v", err)
	}
	trimmed := identity.Trimmed()
	if trimmed.Landscape != "lapras" || trimmed.Platform != "platform" ||
		trimmed.Service != "service" || trimmed.Module != "module" || trimmed.Version != "1.2.3" {
		t.Fatalf("identity was not trimmed: %#v", trimmed)
	}
	want := map[string]string{
		"deployment.environment.name": "lapras",
		"service.namespace":           "platform",
		"service.name":                "service",
		"service.version":             "1.2.3",
		"atomi.landscape":             "lapras",
		"atomi.platform":              "platform",
		"atomi.service":               "service",
		"atomi.module":                "module",
		"atomi.version":               "1.2.3",
	}
	got, err := otel.ResourceAttributes(identity)
	if err != nil || !maps.Equal(got, want) {
		t.Fatalf("resource mapping mismatch:\nwant %#v\ngot  %#v (%v)", want, got, err)
	}
	if otel.AttrDeploymentEnvironmentName != "deployment.environment.name" ||
		otel.AttrServiceNamespace != "service.namespace" ||
		otel.AttrServiceName != "service.name" || otel.AttrServiceVersion != "service.version" {
		t.Fatal("semantic-convention constants changed")
	}

	coordinates := []func(*otel.AppIdentity){
		func(value *otel.AppIdentity) { value.Landscape = " " },
		func(value *otel.AppIdentity) { value.Platform = " " },
		func(value *otel.AppIdentity) { value.Service = " " },
		func(value *otel.AppIdentity) { value.Module = " " },
		func(value *otel.AppIdentity) { value.Version = " " },
	}
	for _, blank := range coordinates {
		candidate := identity
		blank(&candidate)
		assertProblemID(t, candidate.Validate(), otel.FaultIdentityInvalid)
		_, mappingErr := otel.ResourceAttributes(candidate)
		assertProblemID(t, mappingErr, otel.FaultIdentityInvalid)
	}
}

func TestParseAndResolveResourceAttributes(t *testing.T) {
	t.Parallel()

	parsed := otel.ParseResourceAttributes(" key = first,service.name=from-list,bad,=missing, key=last, empty= ")
	wantParsed := map[string]string{"key": "last", "service.name": "from-list", "empty": ""}
	if !maps.Equal(parsed, wantParsed) {
		t.Fatalf("unexpected parsed attributes %#v", parsed)
	}
	if got := otel.ParseResourceAttributes(" , "); len(got) != 0 {
		t.Fatalf("blank list must produce no attributes: %#v", got)
	}

	identity := otel.AppIdentity{
		Landscape: "lapras",
		Platform:  "platform",
		Service:   "service",
		Module:    "module",
		Version:   "1.2.3",
	}
	system := systemWith(map[string]string{
		otel.EnvResourceAttributes: "service.namespace=override,custom=value",
		otel.EnvServiceName:        " environment-service ",
	})
	resolved, err := otel.ResolvedResourceAttributes(identity, system)
	if err != nil {
		t.Fatalf("resource resolution failed: %v", err)
	}
	if resolved[otel.AttrServiceNamespace] != "override" ||
		resolved[otel.AttrServiceName] != "environment-service" || resolved["custom"] != "value" {
		t.Fatalf("resource overrides not applied: %#v", resolved)
	}

	blankService := systemWith(map[string]string{otel.EnvServiceName: " "})
	resolved, err = otel.ResolvedResourceAttributes(identity, blankService)
	if err != nil || resolved[otel.AttrServiceName] != "service" {
		t.Fatalf("blank service override must be ignored: %#v, %v", resolved, err)
	}

	broken := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	sentinel := errors.New("resource env failed")
	broken.EnqueueEnvironmentResult(nil, sentinel)
	_, err = otel.ResolvedResourceAttributes(identity, broken)
	if !errors.Is(err, sentinel) {
		t.Fatalf("expected resource env failure, got %v", err)
	}
	broken = testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	broken.EnqueueEnvironmentResult(nil, nil)
	broken.EnqueueEnvironmentResult(nil, sentinel)
	_, err = otel.ResolvedResourceAttributes(identity, broken)
	if !errors.Is(err, sentinel) {
		t.Fatalf("expected service-name env failure, got %v", err)
	}
	invalid := identity
	invalid.Module = ""
	_, err = otel.ResolvedResourceAttributes(invalid, systemWith(nil))
	assertProblemID(t, err, otel.FaultIdentityInvalid)
}
