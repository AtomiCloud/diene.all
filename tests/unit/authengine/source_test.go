package authengine_test

import (
	"context"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

func TestSessionSourceCarriesTheSessionVerbatim(t *testing.T) {
	t.Parallel()

	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	session := authengine.Session{Subject: "user-1", RefreshToken: "refresh-1"}
	source := authengine.NewSessionSource(provider, session)

	if source.Session().Subject != "user-1" || source.Session().RefreshToken != "refresh-1" {
		t.Fatalf("expected the session to be readable, got %+v", source.Session())
	}

	token, err := source.Mint(context.Background(), sampleResources()[0])
	requireNoError(t, err)
	if token.Resource != "alcohol-zinc" {
		t.Fatalf("expected the resource to be stamped, got %q", token.Resource)
	}

	calls := provider.ResourceTokenCalls()
	if len(calls) != 1 || calls[0].Subject != "user-1" || calls[0].RefreshToken != "refresh-1" {
		t.Fatalf("expected the session to reach the provider unchanged, got %+v", calls)
	}
}

func TestClientCredentialsSourceMintsWithoutASubject(t *testing.T) {
	t.Parallel()

	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	source := authengine.NewClientCredentialsSource(provider)

	token, err := source.Mint(context.Background(), sampleResources()[0])
	requireNoError(t, err)
	if token.Value == "" {
		t.Fatal("expected a machine-to-machine token")
	}

	// A client-credentials token represents the CLIENT: there is deliberately no
	// subject to impersonate, which is why the operator uses this flow.
	calls := provider.ClientCredentialsCalls()
	if len(calls) != 1 || calls[0].Resource.Name != "alcohol-zinc" {
		t.Fatalf("expected one client-credentials call, got %+v", calls)
	}
	if len(provider.ResourceTokenCalls()) != 0 {
		t.Fatal("expected the machine-to-machine flow not to touch the session path")
	}
}

func TestClientCredentialsSourceServesTheOperatorThroughTheSameCache(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	tree, err := authengine.NewResourceTree(problems, sampleResources()...)
	requireNoError(t, err)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})

	// The operator gets the same resource tree, cache, and problem vocabulary as a
	// user-session consumer: only the source differs.
	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    testhelper.NewMemoryTokenStore(),
		Source:   authengine.NewClientCredentialsSource(provider),
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
	})
	requireNoError(t, err)

	tokens, err := cache.All(context.Background())
	requireNoError(t, err)
	if len(tokens) != 2 {
		t.Fatalf("expected a token per backend, got %d", len(tokens))
	}
	if len(provider.ClientCredentialsCalls()) != 2 {
		t.Fatalf("expected one machine-to-machine mint per backend, got %d",
			len(provider.ClientCredentialsCalls()))
	}
}
