package authengine_test

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// blockingSource mints tokens only once a test releases it, so the single-flight
// contract can be proven without a sleep: the leader is guaranteed to be inside the
// mint when the followers arrive.
type blockingSource struct {
	entered chan struct{}
	release chan struct{}
	mutex   sync.Mutex
	minted  int
}

func newBlockingSource() *blockingSource {
	return &blockingSource{entered: make(chan struct{}, 1), release: make(chan struct{})}
}

func (s *blockingSource) Mint(_ context.Context, resource authengine.Resource) (authengine.AccessToken, error) {
	s.entered <- struct{}{}
	<-s.release
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.minted++
	return authengine.AccessToken{
		Value:     "minted",
		Resource:  resource.Name,
		ExpiresAt: testhelper.FixedNow().Add(authengine.AccessTokenLifetime),
	}, nil
}

func (s *blockingSource) Minted() int {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.minted
}

// gatedStore signals after every completed cache read, which is what lets the
// single-flight test order a race without sleeping on it.
type gatedStore struct {
	inner *testhelper.MemoryTokenStore
	reads chan struct{}
}

func (s *gatedStore) Get(ctx context.Context, key string) (authengine.AccessToken, bool, error) {
	token, found, err := s.inner.Get(ctx, key)
	s.reads <- struct{}{}
	return token, found, err
}

func (s *gatedStore) Set(
	ctx context.Context,
	key string,
	token authengine.AccessToken,
	ttl time.Duration,
) error {
	return s.inner.Set(ctx, key, token, ttl)
}

func (s *gatedStore) Delete(ctx context.Context, key string) error {
	return s.inner.Delete(ctx, key)
}

// cacheFixture is a token cache over the fake provider, store, and clock.
type cacheFixture struct {
	cache    *authengine.TokenCache
	provider *testhelper.FakeProvider
	store    *testhelper.MemoryTokenStore
	clock    *mocks.InMemorySystem
	problems *authengine.Problems
}

// newCacheFixture wires a session-backed token cache.
func newCacheFixture(t *testing.T) cacheFixture {
	t.Helper()

	problems := newProblems(t)
	tree, err := authengine.NewResourceTree(problems, sampleResources()...)
	requireNoError(t, err)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	store := testhelper.NewMemoryTokenStore()
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})

	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    store,
		Source:   authengine.NewSessionSource(provider, authengine.Session{Subject: "user-1", RefreshToken: "refresh-1"}),
		Problems: problems,
		Clock:    clock,
	})
	requireNoError(t, err)
	return cacheFixture{cache: cache, provider: provider, store: store, clock: clock, problems: problems}
}

func TestNewTokenCacheRejectsAnIncompleteConfiguration(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	store := testhelper.NewMemoryTokenStore()
	source := authengine.NewClientCredentialsSource(testhelper.NewFakeProvider(testhelper.FakeProviderOptions{}))
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{})

	if _, err := authengine.NewTokenCache(authengine.TokenCacheOptions{}); err == nil {
		t.Fatal("expected a cache without a problem factory to be rejected")
	}

	cases := []struct {
		name    string
		options authengine.TokenCacheOptions
	}{
		{name: "no store", options: authengine.TokenCacheOptions{Problems: problems, Source: source, Clock: clock}},
		{name: "no source", options: authengine.TokenCacheOptions{Problems: problems, Store: store, Clock: clock}},
		{name: "no clock", options: authengine.TokenCacheOptions{Problems: problems, Store: store, Source: source}},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			_, err := authengine.NewTokenCache(testCase.options)
			requireProblem(t, err, authengine.ProblemConfigInvalid)
		})
	}
}

func TestTokenMintsOnceThenServesFromTheCache(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	ctx := context.Background()

	first, err := fixture.cache.Token(ctx, "alcohol-zinc")
	requireNoError(t, err)
	second, err := fixture.cache.Token(ctx, "alcohol-zinc")
	requireNoError(t, err)

	if first.Value != second.Value {
		t.Fatalf("expected the cached token to be served again, got %q then %q", first.Value, second.Value)
	}
	if fixture.provider.Minted() != 1 {
		t.Fatalf("expected exactly one mint, got %d", fixture.provider.Minted())
	}
	if first.Resource != "alcohol-zinc" {
		t.Fatalf("expected the token to be stamped with its resource, got %q", first.Resource)
	}
	if keys := fixture.store.Keys(); len(keys) != 1 || keys[0] != "auth-token:alcohol-zinc" {
		t.Fatalf("expected one namespaced cache key, got %v", keys)
	}
}

func TestTokenPassesTheSessionRefreshTokenToTheProvider(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)

	_, err := fixture.cache.Token(context.Background(), "alcohol-zinc")
	requireNoError(t, err)

	calls := fixture.provider.ResourceTokenCalls()
	if len(calls) != 1 || calls[0].RefreshToken != "refresh-1" || calls[0].Subject != "user-1" {
		t.Fatalf("expected the session to be presented to the provider, got %+v", calls)
	}
	if calls[0].Resource.Indicator != "https://api.zinc.invalid" {
		t.Fatalf("expected the resource indicator to be presented, got %q", calls[0].Resource.Indicator)
	}
}

func TestTokenRefreshesInsideTheSkewWindow(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	ctx := context.Background()

	_, err := fixture.cache.Token(ctx, "alcohol-zinc")
	requireNoError(t, err)

	// Advance to inside the skew window: the cached token is technically still valid
	// but must not be handed out, or a caller receives a token that dies mid-request.
	fixture.clock.SetNow(testhelper.FixedNow().
		Add(authengine.AccessTokenLifetime - authengine.DefaultRefreshSkew/2))

	_, err = fixture.cache.Token(ctx, "alcohol-zinc")
	requireNoError(t, err)

	if fixture.provider.Minted() != 2 {
		t.Fatalf("expected a re-mint inside the skew window, got %d mints", fixture.provider.Minted())
	}
}

func TestTokenRejectsAnUndeclaredResource(t *testing.T) {
	t.Parallel()

	_, err := newCacheFixture(t).cache.Token(context.Background(), "absent")
	requireProblem(t, err, authengine.ProblemResourceUnregistered)
}

func TestTokenSurfacesStoreAndClockFailures(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	fixture.store.EnqueueError(errFake)

	_, err := fixture.cache.Token(context.Background(), "alcohol-zinc")
	requireProblem(t, err, authengine.ProblemProviderUnavailable)

	fixture.clock.EnqueueClockResult(time.Time{}, errFake)
	_, err = fixture.cache.Token(context.Background(), "alcohol-zinc")
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestTokenSurfacesAMintFailureUnchanged(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	fixture.provider.EnqueueResourceTokenError(errFake)

	_, err := fixture.cache.Token(context.Background(), "alcohol-zinc")
	if err == nil {
		t.Fatal("expected the provider failure to surface")
	}
	if fixture.store.Keys() != nil && len(fixture.store.Keys()) != 0 {
		t.Fatalf("expected nothing to be cached after a failed mint, got %v", fixture.store.Keys())
	}
}

func TestTokenSurfacesACacheWriteFailure(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	// The read succeeds (miss), then the write after minting fails.
	fixture.store.EnqueueError(nil)
	fixture.store.EnqueueError(errFake)

	_, err := fixture.cache.Token(context.Background(), "alcohol-zinc")
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestTokenSurfacesAClockFailureAfterMinting(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	// The first read of the clock succeeds; the one taken to compute the cache TTL
	// after minting fails.
	fixture.clock.EnqueueClockResult(testhelper.FixedNow(), nil)
	fixture.clock.EnqueueClockResult(time.Time{}, errFake)

	_, err := fixture.cache.Token(context.Background(), "alcohol-zinc")
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestConcurrentMissesCollapseIntoOneMint(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	tree, err := authengine.NewResourceTree(problems, sampleResources()...)
	requireNoError(t, err)
	source := newBlockingSource()
	store := &gatedStore{inner: testhelper.NewMemoryTokenStore(), reads: make(chan struct{}, 16)}

	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    store,
		Source:   source,
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
	})
	requireNoError(t, err)

	ctx := context.Background()
	const followers = 4
	results := make(chan authengine.AccessToken, followers+1)
	failures := make(chan error, followers+1)

	go func() {
		token, err := cache.Token(ctx, "alcohol-zinc")
		results <- token
		failures <- err
	}()

	// Order the race deterministically rather than sleeping on it: the leader is
	// parked inside the mint, and each follower is only released once its own cache
	// read has completed — so every follower's next move is to join the in-flight
	// call, and the leader cannot have finished and cleared it.
	<-source.entered
	<-store.reads

	var waitGroup sync.WaitGroup
	for range followers {
		waitGroup.Go(func() {
			token, err := cache.Token(ctx, "alcohol-zinc")
			results <- token
			failures <- err
		})
	}
	for range followers {
		<-store.reads
	}

	close(source.release)
	waitGroup.Wait()

	for range followers + 1 {
		requireNoError(t, <-failures)
		if token := <-results; token.Value != "minted" {
			t.Fatalf("expected every caller to observe the one minted token, got %q", token.Value)
		}
	}
	if source.Minted() != 1 {
		t.Fatalf("expected exactly one mint under %d concurrent callers, got %d",
			followers+1, source.Minted())
	}
}

func TestAllResolvesEveryDeclaredResourceEagerly(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)

	tokens, err := fixture.cache.All(context.Background())
	requireNoError(t, err)

	if len(tokens) != 2 {
		t.Fatalf("expected a token per declared resource, got %d", len(tokens))
	}
	for _, name := range []string{"alcohol-zinc", "nitroso-tin"} {
		if tokens[name].Resource != name {
			t.Fatalf("expected a token for %q, got %+v", name, tokens[name])
		}
	}
	if fixture.provider.Minted() != 2 {
		t.Fatalf("expected one mint per resource, got %d", fixture.provider.Minted())
	}
}

func TestAllSurfacesTheFirstFailure(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	fixture.provider.EnqueueResourceTokenError(errFake)

	if _, err := fixture.cache.All(context.Background()); err == nil {
		t.Fatal("expected the batch to surface a per-resource failure")
	}
}

func TestInvalidateEvictsOneResource(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	ctx := context.Background()

	_, err := fixture.cache.Token(ctx, "alcohol-zinc")
	requireNoError(t, err)
	requireNoError(t, fixture.cache.Invalidate(ctx, "alcohol-zinc"))

	if keys := fixture.store.Keys(); len(keys) != 0 {
		t.Fatalf("expected the cache entry to be evicted, got %v", keys)
	}

	_, err = fixture.cache.Token(ctx, "alcohol-zinc")
	requireNoError(t, err)
	if fixture.provider.Minted() != 2 {
		t.Fatalf("expected a re-mint after invalidation, got %d mints", fixture.provider.Minted())
	}
}

func TestInvalidateSurfacesAStoreFailure(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)
	fixture.store.EnqueueError(errFake)

	requireProblem(t,
		fixture.cache.Invalidate(context.Background(), "alcohol-zinc"),
		authengine.ProblemProviderUnavailable)
}

func TestKeyRejectsAResourceNameThatCannotBeAKey(t *testing.T) {
	t.Parallel()

	fixture := newCacheFixture(t)

	// A name that slugifies to nothing cannot be namespaced, and a cache that filed
	// it anyway would collide every such resource under one key.
	_, err := fixture.cache.Key("!!!")
	requireProblem(t, err, authengine.ProblemConfigInvalid)

	requireProblem(t,
		fixture.cache.Invalidate(context.Background(), "!!!"),
		authengine.ProblemConfigInvalid)
}

func TestKeyIsNamespaced(t *testing.T) {
	t.Parallel()

	key, err := newCacheFixture(t).cache.Key("alcohol-zinc")
	requireNoError(t, err)
	if key != "auth-token:alcohol-zinc" {
		t.Fatalf("expected a namespaced key, got %q", key)
	}
}

func TestTokenCacheHonoursConfiguredOverrides(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	tree, err := authengine.NewResourceTree(problems, sampleResources()...)
	requireNoError(t, err)

	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:        tree,
		Store:       testhelper.NewMemoryTokenStore(),
		Source:      authengine.NewClientCredentialsSource(testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})),
		Problems:    problems,
		Clock:       mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
		Namespace:   "operator",
		Skew:        time.Second,
		Concurrency: 1,
	})
	requireNoError(t, err)

	key, err := cache.Key("alcohol-zinc")
	requireNoError(t, err)
	if key != "operator:alcohol-zinc" {
		t.Fatalf("expected the configured namespace, got %q", key)
	}
	if _, err := cache.All(context.Background()); err != nil {
		t.Fatalf("expected the batch to run at concurrency 1, got %v", err)
	}
}

func TestTokenCacheSatisfiesTheRetrieverSeam(t *testing.T) {
	t.Parallel()

	var retriever authengine.Retriever = newCacheFixture(t).cache

	token, err := retriever.Token(context.Background(), "alcohol-zinc")
	requireNoError(t, err)
	if token.Value == "" {
		t.Fatal("expected a token through the retriever seam")
	}
}

func TestAccessTokenExpiryHelpers(t *testing.T) {
	t.Parallel()

	now := testhelper.FixedNow()
	token := authengine.AccessToken{ExpiresAt: now.Add(time.Minute)}

	if token.Expired(now, 0) {
		t.Fatal("expected a live token not to be expired")
	}
	if !token.Expired(now, 2*time.Minute) {
		t.Fatal("expected a skew wider than the remaining life to expire the token")
	}
	if token.TTL(now) != time.Minute {
		t.Fatalf("expected a one-minute TTL, got %s", token.TTL(now))
	}
	if token.TTL(now.Add(2*time.Minute)) != 0 {
		t.Fatal("expected a spent token's TTL to clamp at zero")
	}
}

func TestTokenRejectsADeclaredNameThatCannotBeACacheKey(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	// A name that is non-blank but slugifies to nothing passes tree validation and
	// only fails at key derivation, which must be reported rather than collapsed
	// into a shared key.
	tree, err := authengine.NewResourceTree(problems, authengine.Resource{
		Name: "!!!", Indicator: "https://api.invalid",
	})
	requireNoError(t, err)

	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    testhelper.NewMemoryTokenStore(),
		Source:   authengine.NewClientCredentialsSource(testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})),
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
	})
	requireNoError(t, err)

	_, err = cache.Token(context.Background(), "!!!")
	requireProblem(t, err, authengine.ProblemConfigInvalid)
}
