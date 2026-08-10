package problem_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func examplePortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.raichu.cluster.atomi.cloud",
		Landscape: "raichu",
		Platform:  "go",
		Service:   "user",
		Module:    "api",
	}
}

// ExampleTypeURI shows the single-source type-URI builder expanding the
// C0 §2 template (with the deliberate {version} segment).
func ExampleTypeURI() {
	uri, _ := problem.TypeURI(examplePortal(), "v1", "entity-not-found")
	fmt.Println(uri)
	// Output: https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found
}

// ExampleInvalidSegmentError shows the boundary validation rejecting a segment
// that contains a slash.
func ExampleInvalidSegmentError() {
	_, err := problem.TypeURI(problem.LocalErrorPortal(), "v1", "bad/id")
	var segmentErr *problem.InvalidSegmentError
	if errors.As(err, &segmentErr) {
		fmt.Println(segmentErr.Name)
	}
	// Output: id
}

// ExampleProblem shows the RFC 9457 envelope marshalling to its canonical wire
// shape (keys are emitted in encoding/json's sorted order).
func ExampleProblem() {
	envelope := problem.Problem{
		Type:        "https://docs.example/v1/entity-not-found",
		Title:       "Entity not found",
		Status:      404,
		Recoverable: false,
		Data:        map[string]any{"resource": "user"},
	}
	data, _ := json.Marshal(envelope)
	fmt.Println(string(data))
	// Output: {"data":{"resource":"user"},"recoverable":false,"status":404,"title":"Entity not found","type":"https://docs.example/v1/entity-not-found"}
}

// ExampleProblem_String shows the compact human-readable form.
func ExampleProblem_String() {
	envelope := problem.Problem{Type: "https://x/v1/conflict", Title: "Conflict", Status: 409}
	fmt.Println(envelope.String())
	// Output: Problem(https://x/v1/conflict, 409, Conflict)
}

// ExampleError shows recovering a Problem from a wrapped (T, error)
// result via errors.As — the Go realization of the family result slot.
func ExampleError() {
	envelope := problem.Problem{Type: "https://x/v1/conflict", Title: "Conflict", Status: 409}
	err := fmt.Errorf("saving user: %w", problem.NewError(envelope))

	var problemErr *problem.Error
	if errors.As(err, &problemErr) {
		fmt.Println(problemErr.Problem.Status)
	}
	// Output: 409
}

// ExampleRegistry shows registering the generic baseline and resolving a
// type URI through the single-source builder.
func ExampleRegistry() {
	registry, _ := problem.NewRegistry(examplePortal())
	_ = problem.RegisterGenerics(registry)

	entityNotFound, _ := registry.Require("entity-not-found")
	uri, _ := registry.TypeURIFor(entityNotFound)
	fmt.Println(uri)
	// Output: https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found
}

// ExampleGenericProblems lists the portable v1 baseline catalog in stable order.
func ExampleGenericProblems() {
	for _, problemType := range problem.GenericProblems() {
		fmt.Println(problemType.ID)
	}
	// Output:
	// validation-error
	// entity-not-found
	// conflict
	// unauthenticated
	// unauthorized
	// invalid-json
}

// ExampleCatalog shows building the C0 §14 Problem CR content for an
// endpoint that can return a generic problem.
func ExampleCatalog() {
	catalog := problem.NewCatalog(examplePortal())
	_ = catalog.AddType(problem.EntityNotFound(), problem.CatalogEndpoint{Method: "GET", Path: "/user/{id}"})

	content := catalog.ToCRDContent()
	fmt.Println(content[0]["id"], content[0]["status"], content[0]["recoverable"])
	// Output: entity-not-found 404 false
}

// ExampleFromObject shows the total value→Problem fold producing an uncatalogued
// 5xx problem for an unrecognised error (C0 §14).
func ExampleFromObject() {
	envelope := problem.FromObject(errors.New("disk full"), problem.DefaultTransformOptions())
	fmt.Println(envelope.Status, *envelope.Detail)
	// Output: 500 disk full
}

// ExampleLocalError shows wrapping an unexpected error into a local-error
// Problem carrying the message and stack in data.
func ExampleLocalError() {
	local := problem.NewLocalError(problem.NoopErrorSink{})
	envelope, _ := local.Wrap(context.Background(), errors.New("boom"), "goroutine 1 [running]")
	fmt.Println(envelope.Type)
	fmt.Println(envelope.Data["message"])
	// Output:
	// https://local.atomi.cloud/docs/local/go/app/core/v1/local-error
	// boom
}
