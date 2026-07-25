package testhelper_test

import (
	"context"
	"fmt"
	"net/http"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
)

// Invoice is the payload the examples decode.
type Invoice struct {
	ID    string `json:"id"`
	Total int    `json:"total"`
}

// A whole multi-backend tree over fakes, in one call — with each backend's own
// token attached through the auth-engine retriever seam.
func ExampleNewFakeTree() {
	route := map[string]testhelper.Route{
		"/v1/invoices/i-1": {Status: http.StatusOK, Body: Invoice{ID: "i-1", Total: 4200}},
	}
	billing := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Routes: route})
	catalog := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Routes: route})

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{
			"billing": billing,
			"catalog": catalog,
		},
		Tokens: map[string]string{
			"billing": "token-billing",
			"catalog": "token-catalog",
		},
	})
	if err != nil {
		panic(err)
	}
	defer tree.Close()

	client, err := tree.Tree.Backend("billing")
	if err != nil {
		panic(err)
	}
	invoice, err := apiengine.Execute[Invoice](context.Background(), client,
		apiengine.Request{Path: "/v1/invoices/i-1"})
	if err != nil {
		panic(err)
	}

	fmt.Println(invoice.ID, invoice.Total)
	fmt.Println(billing.Requests()[0].Authorization())
	// Output:
	// i-1 4200
	// Bearer token-billing
}

// Canned mints the RFC 9457 envelope a 4xx test needs, so a test asserts how a
// problem travels without first becoming an expert on the wire shape.
func ExampleCanned() {
	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/v1/invoices/i-9": testhelper.Canned(testhelper.ProblemOptions{
				Type:        "https://docs.example.com/docs/prod/api/billing/core/v1/quota-exceeded",
				Title:       "Quota exceeded",
				Status:      http.StatusTooManyRequests,
				Detail:      "the monthly quota is spent",
				Recoverable: true,
				Data:        map[string]any{"limit": 100},
			}),
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"billing": backend},
	})
	if err != nil {
		panic(err)
	}
	client, err := tree.Tree.Backend("billing")
	if err != nil {
		panic(err)
	}

	_, err = apiengine.Execute[Invoice](context.Background(), client,
		apiengine.Request{Path: "/v1/invoices/i-9"})

	// CheckProblem is the *testing.T-free half, so it works in an example.
	envelope, checkErr := testhelper.CheckProblem(err, testhelper.ProblemOptions{
		Title:  "Quota exceeded",
		Status: http.StatusTooManyRequests,
	})
	fmt.Println(checkErr == nil)
	fmt.Println(envelope.Data["limit"])
	// Output:
	// true
	// 100
}

// A backend can be told to fail the transport, which is how the
// retry-once-on-network-error profile is proven without a real network to
// break.
func ExampleFakeBackend_Count() {
	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/v1/invoices/i-1": {Status: http.StatusOK, Body: Invoice{ID: "i-1", Total: 4200}},
		},
		TransportFailures: 1,
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"billing": backend},
		Retry:    apiengine.RetryConfig{Network: true},
	})
	if err != nil {
		panic(err)
	}
	client, err := tree.Tree.Backend("billing")
	if err != nil {
		panic(err)
	}

	invoice, err := apiengine.Execute[Invoice](context.Background(), client,
		apiengine.Request{Path: "/v1/invoices/i-1"})
	if err != nil {
		panic(err)
	}

	fmt.Println(invoice.ID)
	// Exactly two: the original attempt and the one permitted retry.
	fmt.Println(backend.Count())
	// Output:
	// i-1
	// 2
}
