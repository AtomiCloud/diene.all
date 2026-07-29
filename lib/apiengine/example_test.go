package apiengine_test

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// Account is the kind of payload a caller decodes a backend response into.
type Account struct {
	ID   string `json:"id"`
	Plan string `json:"plan"`
}

// A consumer registers every backend it onboards to in one config block, and
// resolves a client per backend from the resulting tree.
func ExampleNewClientTree() {
	problems, err := apiengine.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		panic(err)
	}

	config := apiengine.DefaultConfig()
	config.Backends["billing"] = apiengine.BackendConfig{
		BaseURL:   "https://billing.example.com",
		Indicator: "https://billing.example.com/api",
		Scopes:    []string{"invoice.read"},
		Timeout:   wire.Duration(10 * time.Second),
	}
	config.Backends["catalog"] = apiengine.BackendConfig{
		BaseURL: "https://catalog.example.com",
	}

	tree, err := apiengine.NewClientTree(apiengine.TreeOptions{
		Config:   config,
		Problems: problems,
		// Tokens: a *authengine.TokenCache, which satisfies
		// authengine.Retriever and resolves a token per backend.
	})
	if err != nil {
		panic(err)
	}

	fmt.Println(tree.Names())
	client, err := tree.Backend("billing")
	if err != nil {
		panic(err)
	}
	fmt.Println(client.BaseURL())
	// Output:
	// [billing catalog]
	// https://billing.example.com
}

// Execute maps the three cases onto Go's ordinary (T, error) pair: a 2xx
// decodes into T, and anything else arrives as an error.
func ExampleExecute() {
	backend := newExampleBackend()
	defer backend.Close()

	client := newExampleClient(backend.URL())

	account, err := apiengine.Execute[Account](context.Background(), client,
		apiengine.Request{Path: "/v1/accounts/a-1"})
	if err != nil {
		panic(err)
	}
	fmt.Println(account.ID, account.Plan)
	// Output: a-1 pro
}

// A 4xx arrives as the backend's OWN envelope, with the `data` extension it
// published still intact — recover it with errors.As.
func ExampleExecute_problem() {
	backend := newExampleBackend()
	defer backend.Close()

	client := newExampleClient(backend.URL())

	_, err := apiengine.Execute[Account](context.Background(), client,
		apiengine.Request{Path: "/v1/accounts/missing"})

	var carried *problem.Error
	if errors.As(err, &carried) {
		fmt.Println(carried.Problem.Title)
		fmt.Println(carried.Problem.Status)
		fmt.Println(carried.Problem.Data["accountId"])
	}
	// Output:
	// Account not found
	// 404
	// missing
}

// Classify is the 3-case rule on its own, for a caller driving the transport
// itself.
func ExampleClassify() {
	fmt.Println(apiengine.Classify(200, nil))
	fmt.Println(apiengine.Classify(404, nil))
	fmt.Println(apiengine.Classify(503, nil))
	fmt.Println(apiengine.Classify(0, errors.New("connection refused")))
	// Output:
	// success
	// problem
	// transport
	// transport
}

// The engine publishes the schema of its own config block; a consumer composes
// it into its root schema alongside the other engines' blocks.
func ExampleConfigBlockSchema() {
	properties := map[string]any{
		apiengine.ConfigBlockKey: apiengine.ConfigBlockSchema(),
		// "auth": authengine.ConfigBlockSchema(), and so on.
	}
	root := map[string]any{
		"type":       "object",
		"properties": properties,
	}

	fmt.Println(root["type"])
	fmt.Println(apiengine.ConfigBlockKey, properties[apiengine.ConfigBlockKey] != nil)
	// Output:
	// object
	// api true
}

// The resilience profile is one retry on a network error — never on a 5xx, and
// never more than once.
func ExampleRetryConfig() {
	config := apiengine.DefaultConfig()
	config.Retry = apiengine.RetryConfig{
		Network: true,
		Delay:   wire.Duration(200 * time.Millisecond),
	}
	fmt.Println(config.Retry.Network, config.Retry.Delay)
	// Output: true PT0.2S
}

// Problems mints the engine's own failures through the consumer's error portal.
func ExampleProblems_Raise() {
	problems, err := apiengine.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		panic(err)
	}

	raised := problems.Raise(apiengine.ProblemBackendUnregistered,
		"no backend is registered as ledger",
		map[string]any{"backend": "ledger"})

	var carried *problem.Error
	if errors.As(raised, &carried) {
		fmt.Println(carried.Problem.Title)
		fmt.Println(carried.Problem.Type)
	}
	// Output:
	// Backend not registered
	// https://local.atomi.cloud/docs/local/go/app/core/v1/backend-unregistered
}

// newExampleBackend starts a backend serving one account and one C0-conformant
// 404, so the examples above have something real to call.
func newExampleBackend() *testhelper.FakeBackend {
	return testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/v1/accounts/a-1": {
				Status: http.StatusOK,
				Body:   Account{ID: "a-1", Plan: "pro"},
			},
			"/v1/accounts/missing": testhelper.Canned(testhelper.ProblemOptions{
				Type:   "https://docs.example.com/docs/prod/api/billing/core/v1/account-not-found",
				Title:  "Account not found",
				Status: http.StatusNotFound,
				Data:   map[string]any{"accountId": "missing"},
			}),
		},
	})
}

// newExampleClient builds a client against the given origin.
func newExampleClient(base string) *apiengine.Client {
	problems, err := apiengine.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		panic(err)
	}
	client, err := apiengine.NewClient(apiengine.ClientOptions{
		Backend:  "accounts",
		Config:   apiengine.BackendConfig{BaseURL: base},
		Doer:     http.DefaultClient,
		Problems: problems,
	})
	if err != nil {
		panic(err)
	}
	return client
}
