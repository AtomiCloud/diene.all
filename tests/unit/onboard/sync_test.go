package onboard_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// errFake is the failure the fakes' scripted queues raise.
var errFake = errors.New("scripted failure")

// backends are the two registered backends every round runs against; one backend
// could never prove per-backend independence.
func backends() []authengine.Resource {
	return []authengine.Resource{
		{Name: "alcohol-zinc", Indicator: "https://api.zinc.invalid"},
		{Name: "nitroso-tin", Indicator: "https://api.tin.invalid"},
	}
}

// principal builds a mapped identity registered against the named backends.
func principal(registered ...string) authengine.Principal {
	claims := authengine.Claims{
		authengine.ClaimSubject:  "user-1",
		authengine.ClaimUsername: "owner",
		authengine.ClaimEmail:    "owner@example.invalid",
		onboard.RawIDTokenClaim:  "raw-id-token",
	}
	for _, backend := range registered {
		claims[authengine.RegistrationClaim(backend)] = "true"
	}
	return authengine.NewClaimMapper().Map(claims)
}

// fixture is an onboarding round over the shipped fakes.
type fixture struct {
	sync      onboard.Sync
	zinc      *testhelper.FakeBackend
	tin       *testhelper.FakeBackend
	provider  *testhelper.FakeProvider
	refresher *testhelper.FakeRefresher
	problems  *authengine.Problems
}

// newFixture wires an onboarding round whose refresher reports every backend
// registered, which is the happy path.
func newFixture(t *testing.T, refreshed authengine.Principal) fixture {
	t.Helper()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	tree, err := authengine.NewResourceTree(problems, backends()...)
	requireNoError(t, err)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})

	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    testhelper.NewMemoryTokenStore(),
		Source:   authengine.NewClientCredentialsSource(provider),
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
	})
	requireNoError(t, err)

	zinc := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"})
	tin := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "nitroso-tin"})
	refresher := testhelper.NewFakeRefresher(refreshed)

	round, err := onboard.NewSync(onboard.SyncOptions{
		Backends:  []onboard.Backend{zinc, tin},
		Claims:    provider,
		Refresher: refresher,
		Tokens:    cache,
		Problems:  problems,
	})
	requireNoError(t, err)
	return fixture{sync: round, zinc: zinc, tin: tin, provider: provider, refresher: refresher, problems: problems}
}

func requireNoError(t *testing.T, err error) {
	t.Helper()

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestNewSyncRejectsAnIncompleteConfiguration(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	backend := []onboard.Backend{testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "zinc"})}
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	refresher := testhelper.NewFakeRefresher(principal())

	if _, err := onboard.NewSync(onboard.SyncOptions{}); err == nil {
		t.Fatal("expected a round without a problem factory to be rejected")
	}
	if _, err := onboard.NewSync(onboard.SyncOptions{Problems: problems}); !errors.Is(err, onboard.ErrNoBackends) {
		t.Fatalf("expected a round with no backends to be rejected, got %v", err)
	}

	cases := []struct {
		name    string
		options onboard.SyncOptions
	}{
		{
			name: "no claim writer",
			options: onboard.SyncOptions{
				Problems: problems, Backends: backend, Refresher: refresher, Tokens: nil,
			},
		},
		{
			name: "no refresher",
			options: onboard.SyncOptions{
				Problems: problems, Backends: backend, Claims: provider,
			},
		},
		{
			name: "no token retriever",
			options: onboard.SyncOptions{
				Problems: problems, Backends: backend, Claims: provider, Refresher: refresher,
			},
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			_, err := onboard.NewSync(testCase.options)
			if _, failure := testhelper.CheckAuthProblem(err, authengine.ProblemConfigInvalid); failure != nil {
				t.Fatalf("%v", failure)
			}
		})
	}
}

func TestRunRequiresAnAuthenticatedSubject(t *testing.T) {
	t.Parallel()

	round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))

	_, err := round.sync.Run(context.Background(), authengine.Principal{})
	if _, failure := testhelper.CheckAuthProblem(err, authengine.ProblemTokenClaimMissing); failure != nil {
		t.Fatalf("%v", failure)
	}
}

func TestAPresentClaimIsTheFastPath(t *testing.T) {
	t.Parallel()

	round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))

	states, err := round.sync.Run(context.Background(), principal("alcohol-zinc", "nitroso-tin"))
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseReady)
	testhelper.AssertPhase(t, states, "nitroso-tin", onboard.PhaseReady)

	// Claims-first means exactly that: a registered caller runs no registration work
	// at all — no probe, no create, no claim write-back.
	if len(round.zinc.Registrations()) != 0 || len(round.tin.Registrations()) != 0 {
		t.Fatal("expected a registered caller not to be registered again")
	}
	if len(round.provider.ClaimCalls()) != 0 {
		t.Fatal("expected no claim write-back for an already-registered caller")
	}
	if len(round.refresher.Calls()) != 0 {
		t.Fatal("expected no forced refresh for an already-registered caller")
	}
	if !states["alcohol-zinc"].Ready() {
		t.Fatal("expected the ready helper to agree with the phase")
	}
}

func TestAnAbsentClaimRunsCreateWriteBackAndReverify(t *testing.T) {
	t.Parallel()

	round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))

	states, err := round.sync.Run(context.Background(), principal())
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseReady)
	if !states["alcohol-zinc"].Created || !states["alcohol-zinc"].ClaimWritten {
		t.Fatalf("expected the round to record what it did, got %+v", states["alcohol-zinc"])
	}

	registrations := round.zinc.Registrations()
	if len(registrations) != 1 {
		t.Fatalf("expected one registration, got %d", len(registrations))
	}
	if registrations[0].Subject != "user-1" || registrations[0].Username != "owner" {
		t.Fatalf("expected the identity to reach the backend, got %+v", registrations[0])
	}
	// The raw tokens travel as DATA so the backend re-validates them itself.
	if registrations[0].AccessToken == "" || registrations[0].IDToken != "raw-id-token" {
		t.Fatalf("expected both raw tokens to be forwarded, got %+v", registrations[0])
	}

	claims := round.provider.ClaimCalls()
	if len(claims) != 2 {
		t.Fatalf("expected one claim write-back per backend, got %d", len(claims))
	}
	if claims[0].Name != "alcohol_zinc" || claims[0].Value != "true" {
		t.Fatalf("expected the derived registration claim, got %+v", claims[0])
	}
	if len(round.refresher.Calls()) != 2 {
		t.Fatalf("expected a forced refresh per backend, got %d", len(round.refresher.Calls()))
	}
}

func TestAnExistingRowIsTheCreateTimeRaceOnly(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	tree, err := authengine.NewResourceTree(problems, backends()[:1]...)
	requireNoError(t, err)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    testhelper.NewMemoryTokenStore(),
		Source:   authengine.NewClientCredentialsSource(provider),
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
	})
	requireNoError(t, err)

	// The row already exists: a concurrent first sign-in got there first.
	zinc := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc", Exists: true})
	round, err := onboard.NewSync(onboard.SyncOptions{
		Backends:  []onboard.Backend{zinc},
		Claims:    provider,
		Refresher: testhelper.NewFakeRefresher(principal("alcohol-zinc")),
		Tokens:    cache,
		Problems:  problems,
	})
	requireNoError(t, err)

	states, err := round.Run(context.Background(), principal())
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseReady)
	if states["alcohol-zinc"].Created {
		t.Fatal("expected the round not to claim it created an existing row")
	}
	if len(zinc.Registrations()) != 0 {
		t.Fatal("expected no create call when the row already exists")
	}
	if !states["alcohol-zinc"].ClaimWritten {
		t.Fatal("expected the claim write-back to run even when the row already existed")
	}
}

func TestAClaimThatNeverAppearsIsAStalledOnboarding(t *testing.T) {
	t.Parallel()

	// The refresher keeps reporting an unregistered principal: treating that as
	// success is exactly the bug the re-verify step exists to catch.
	round := newFixture(t, principal())

	states, err := round.sync.Run(context.Background(), principal())
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseError)
	if _, failure := testhelper.CheckAuthProblem(
		states["alcohol-zinc"].Err, authengine.ProblemOnboardingStalled,
	); failure != nil {
		t.Fatalf("%v", failure)
	}
	// Progress already made is still recorded, so an operator can tell "created but
	// the claim never landed" from "never got off the ground".
	if !states["alcohol-zinc"].Created || !states["alcohol-zinc"].ClaimWritten {
		t.Fatalf("expected the partial progress to be recorded, got %+v", states["alcohol-zinc"])
	}
}

func TestOneBackendFailingNeverAbortsTheOthers(t *testing.T) {
	t.Parallel()

	round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))
	round.zinc.EnqueueCreateError(errFake)

	states, err := round.sync.Run(context.Background(), principal())
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseError)
	testhelper.AssertPhase(t, states, "nitroso-tin", onboard.PhaseReady)
	if states["alcohol-zinc"].Ready() {
		t.Fatal("expected the failed backend not to report ready")
	}
}

func TestEachBackendFailureModeIsReported(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name     string
		sabotage func(fixture)
	}{
		{name: "probe fails", sabotage: func(f fixture) { f.zinc.EnqueueExistsError(errFake) }},
		{name: "create fails", sabotage: func(f fixture) { f.zinc.EnqueueCreateError(errFake) }},
		{name: "claim write-back fails", sabotage: func(f fixture) { f.provider.EnqueueClaimError(errFake) }},
		{name: "refresh fails", sabotage: func(f fixture) { f.refresher.EnqueueError(errFake) }},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))
			testCase.sabotage(round)

			states, err := round.sync.Run(context.Background(), principal())
			requireNoError(t, err)

			testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseError)
			if states["alcohol-zinc"].Err == nil {
				t.Fatal("expected the failure to be carried on the state")
			}
		})
	}
}

func TestATokenFailureKeepsTheBackendOutOfReady(t *testing.T) {
	t.Parallel()

	round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))
	round.provider.EnqueueClientCredentialsError(errFake)

	states, err := round.sync.Run(context.Background(), principal())
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseError)
}

func TestEachBackendIsCalledWithItsOwnToken(t *testing.T) {
	t.Parallel()

	round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))

	_, err := round.sync.Run(context.Background(), principal())
	requireNoError(t, err)

	zincTokens := round.zinc.Tokens()
	tinTokens := round.tin.Tokens()
	if len(zincTokens) == 0 || len(tinTokens) == 0 {
		t.Fatal("expected both backends to be called")
	}
	if zincTokens[0].Resource != "alcohol-zinc" || tinTokens[0].Resource != "nitroso-tin" {
		t.Fatalf("expected per-backend tokens, got %q and %q",
			zincTokens[0].Resource, tinTokens[0].Resource)
	}
	if zincTokens[0].Value == tinTokens[0].Value {
		t.Fatal("expected distinct per-resource tokens, not one shared token")
	}
}

func TestRegistrationOmitsAbsentOptionalClaims(t *testing.T) {
	t.Parallel()

	round := newFixture(t, principal("alcohol-zinc", "nitroso-tin"))

	bare := authengine.NewClaimMapper().Map(authengine.Claims{authengine.ClaimSubject: "user-1"})
	_, err := round.sync.Run(context.Background(), bare)
	requireNoError(t, err)

	registrations := round.zinc.Registrations()
	if len(registrations) != 1 {
		t.Fatalf("expected one registration, got %d", len(registrations))
	}
	if registrations[0].Username != "" || registrations[0].Email != "" || registrations[0].IDToken != "" {
		t.Fatalf("expected absent claims to stay absent, got %+v", registrations[0])
	}
}

// bareBackend is a backend with no app-specific second step, which is the shape
// most backends have.
type bareBackend struct {
	inner *testhelper.FakeBackend
}

func (b bareBackend) Name() string { return b.inner.Name() }

func (b bareBackend) Exists(ctx context.Context, token authengine.AccessToken) (bool, error) {
	return b.inner.Exists(ctx, token)
}

func (b bareBackend) Create(
	ctx context.Context,
	token authengine.AccessToken,
	registration onboard.Registration,
) error {
	return b.inner.Create(ctx, token, registration)
}

// newConfigurableRound wires a one-backend round whose backend advertises an
// app-specific configuration step.
func newConfigurableRound(t *testing.T, backend onboard.Backend) onboard.Sync {
	t.Helper()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	tree, err := authengine.NewResourceTree(problems, backends()[:1]...)
	requireNoError(t, err)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    testhelper.NewMemoryTokenStore(),
		Source:   authengine.NewClientCredentialsSource(provider),
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
	})
	requireNoError(t, err)

	round, err := onboard.NewSync(onboard.SyncOptions{
		Backends:  []onboard.Backend{backend},
		Claims:    provider,
		Refresher: testhelper.NewFakeRefresher(principal("alcohol-zinc")),
		Tokens:    cache,
		Problems:  problems,
	})
	requireNoError(t, err)
	return round
}

func TestAnUnconfiguredBackendRestsInNeedsOnboarding(t *testing.T) {
	t.Parallel()

	// Registration is done, but the app-specific step needs real UX a library
	// cannot supply — so the round hands the consumer's gate a signal, not a lie.
	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Name: "alcohol-zinc", NeedsConfiguration: true,
	})
	round := newConfigurableRound(t, backend)

	states, err := round.Run(context.Background(), principal("alcohol-zinc"))
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseNeedsOnboarding)
	if states["alcohol-zinc"].Ready() {
		t.Fatal("expected an unconfigured backend not to report ready")
	}
}

func TestAConfiguredBackendReachesReady(t *testing.T) {
	t.Parallel()

	round := newConfigurableRound(t,
		testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"}))

	states, err := round.Run(context.Background(), principal("alcohol-zinc"))
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseReady)
}

func TestABackendWithNoSecondStepReachesReadyDirectly(t *testing.T) {
	t.Parallel()

	round := newConfigurableRound(t, bareBackend{
		inner: testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"}),
	})

	states, err := round.Run(context.Background(), principal("alcohol-zinc"))
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseReady)
}

func TestSettleReportsItsOwnFailures(t *testing.T) {
	t.Parallel()

	t.Run("configuration probe fails", func(t *testing.T) {
		t.Parallel()

		backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"})
		backend.EnqueueConfiguredError(errFake)
		round := newConfigurableRound(t, backend)

		states, err := round.Run(context.Background(), principal("alcohol-zinc"))
		requireNoError(t, err)
		testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseError)
	})

	t.Run("token resolution fails", func(t *testing.T) {
		t.Parallel()

		problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
		requireNoError(t, err)
		tree, err := authengine.NewResourceTree(problems, backends()[:1]...)
		requireNoError(t, err)
		provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
		provider.EnqueueClientCredentialsError(errFake)
		cache, err := authengine.NewTokenCache(authengine.TokenCacheOptions{
			Tree:     tree,
			Store:    testhelper.NewMemoryTokenStore(),
			Source:   authengine.NewClientCredentialsSource(provider),
			Problems: problems,
			Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
		})
		requireNoError(t, err)
		round, err := onboard.NewSync(onboard.SyncOptions{
			Backends:  []onboard.Backend{testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"})},
			Claims:    provider,
			Refresher: testhelper.NewFakeRefresher(principal("alcohol-zinc")),
			Tokens:    cache,
			Problems:  problems,
		})
		requireNoError(t, err)

		states, err := round.Run(context.Background(), principal("alcohol-zinc"))
		requireNoError(t, err)
		testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseError)
	})
}

func TestARegisteredCallerOnABareBackendCostsNothing(t *testing.T) {
	t.Parallel()

	inner := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"})
	round := newConfigurableRound(t, bareBackend{inner: inner})

	states, err := round.Run(context.Background(), principal("alcohol-zinc"))
	requireNoError(t, err)

	testhelper.AssertPhase(t, states, "alcohol-zinc", onboard.PhaseReady)
	// Claims-first at its cheapest: a backend with no second step is answered from
	// the token alone, with zero API calls.
	if len(inner.Tokens()) != 0 {
		t.Fatalf("expected no backend call at all, got %d", len(inner.Tokens()))
	}
}
