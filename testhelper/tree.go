package testhelper

import (
	"context"
	"errors"
	"maps"
	"sync"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// FakeRetriever is an in-memory [authengine.Retriever]: it hands out a canned
// token per resource and records what was asked for.
//
// A consumer testing the multi-backend tree needs to prove that backend A got
// A's token and backend B got B's — which needs a retriever that answers
// per resource and remembers, not a real IdP.
type FakeRetriever struct {
	mu       sync.Mutex
	tokens   map[string]string
	failures map[string]error
	asked    []string
}

// NewFakeRetriever creates a retriever serving the given resource-to-token map.
func NewFakeRetriever(tokens map[string]string) *FakeRetriever {
	copied := make(map[string]string, len(tokens))
	maps.Copy(copied, tokens)
	return &FakeRetriever{tokens: copied, failures: map[string]error{}}
}

// FailResource makes the named resource fail to resolve, which is how a test
// reaches the credentials-unavailable path without breaking an IdP.
func (r *FakeRetriever) FailResource(resource string, cause error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.failures[resource] = cause
}

// Token implements [authengine.Retriever].
func (r *FakeRetriever) Token(_ context.Context, resource string) (authengine.AccessToken, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.asked = append(r.asked, resource)

	if failure, failing := r.failures[resource]; failing {
		return authengine.AccessToken{}, failure
	}
	value, found := r.tokens[resource]
	if !found {
		return authengine.AccessToken{}, errors.New("testhelper: no token for resource " + resource)
	}
	return authengine.AccessToken{
		Value:     value,
		Resource:  resource,
		IssuedAt:  time.Unix(0, 0).UTC(),
		ExpiresAt: time.Unix(0, 0).UTC().Add(time.Hour),
	}, nil
}

// Asked returns the resources tokens were requested for, oldest first.
func (r *FakeRetriever) Asked() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]string, len(r.asked))
	copy(out, r.asked)
	return out
}

// SampleErrorPortal returns a deterministic error portal for tests.
func SampleErrorPortal() problem.ErrorPortal {
	return problem.LocalErrorPortal()
}

// NewProblems returns an api-engine problem factory on [SampleErrorPortal],
// so a test that only wants to exercise the client need not build one.
//
// Extra types are registered alongside the engine's, exactly as they would be
// in a consumer, so a test can raise its own problems through the same factory.
// A type whose id collides with an engine problem is rejected.
func NewProblems(extra ...problem.Type) (*apiengine.Problems, error) {
	return apiengine.NewProblems(SampleErrorPortal(), extra...)
}

// FakeTree is a running client tree over fake backends.
type FakeTree struct {
	// Tree is the client tree under test.
	Tree *apiengine.ClientTree
	// Backends maps each registered name to its fake backend.
	Backends map[string]*FakeBackend
	// Retriever is the per-backend token seam the tree was built with.
	Retriever *FakeRetriever
	// Problems is the factory the tree mints its errors through.
	Problems *apiengine.Problems
}

// FakeTreeOptions configures [NewFakeTree].
type FakeTreeOptions struct {
	// Backends maps a logical backend name to the fake serving it.
	Backends map[string]*FakeBackend
	// Tokens maps a resource name to the token the retriever hands out. Nil
	// means the tree is built without a retriever, i.e. unauthenticated.
	Tokens map[string]string
	// Retry is the resilience profile. Zero disables the retry, so a test that
	// wants it says so.
	Retry apiengine.RetryConfig
	// ExtraProblems are the consumer's own problem types, registered on the
	// tree's factory alongside the engine's.
	ExtraProblems []problem.Type
}

// NewFakeTree assembles a client tree over the given fake backends.
//
// The retry sleep is replaced with a no-op, so exercising the retry-once
// profile costs no wall-clock time.
func NewFakeTree(options FakeTreeOptions) (*FakeTree, error) {
	problems, err := NewProblems(options.ExtraProblems...)
	if err != nil {
		return nil, err
	}

	config := apiengine.DefaultConfig()
	config.Retry = options.Retry
	for name, backend := range options.Backends {
		config.Backends[name] = backend.Backend()
	}

	var retriever *FakeRetriever
	var tokens authengine.Retriever
	if options.Tokens != nil {
		retriever = NewFakeRetriever(options.Tokens)
		tokens = retriever
	}

	tree, err := apiengine.NewClientTree(apiengine.TreeOptions{
		Config:   config,
		Tokens:   tokens,
		Problems: problems,
		Sleep:    func(time.Duration) {},
	})
	if err != nil {
		return nil, err
	}
	return &FakeTree{
		Tree:      tree,
		Backends:  options.Backends,
		Retriever: retriever,
		Problems:  problems,
	}, nil
}

// Close shuts down every fake backend in the tree.
func (f *FakeTree) Close() {
	for _, backend := range f.Backends {
		backend.Close()
	}
}
