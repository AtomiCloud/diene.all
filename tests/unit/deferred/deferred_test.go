package deferred_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/deferred"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// errFake is the failure the fakes' scripted queues raise.
var errFake = errors.New("scripted failure")

// fixture is a minter over the fake store, provider, and clock.
type fixture struct {
	minter   deferred.Minter
	store    *testhelper.MemoryDeferredStore
	provider *testhelper.FakeProvider
	clock    *mocks.InMemorySystem
	problems *authengine.Problems
}

// newFixture wires a deferred-login minter.
func newFixture(t *testing.T) fixture {
	t.Helper()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	store := testhelper.NewMemoryDeferredStore()
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})

	minter, err := deferred.NewMinter(deferred.MinterOptions{
		Store: store, Provider: provider, Problems: problems, Clock: clock,
	})
	requireNoError(t, err)
	return fixture{minter: minter, store: store, provider: provider, clock: clock, problems: problems}
}

// session is an authenticated session a handoff may be minted from.
func session() authengine.Session {
	return authengine.Session{Subject: "user-1", RefreshToken: "refresh-1"}
}

func requireNoError(t *testing.T, err error) {
	t.Helper()

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func requireProblem(t *testing.T, err error, id string) {
	t.Helper()

	if _, failure := testhelper.CheckAuthProblem(err, id); failure != nil {
		t.Fatalf("%v", failure)
	}
}

func TestNewMinterRejectsAnIncompleteConfiguration(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	store := testhelper.NewMemoryDeferredStore()
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{})

	if _, err := deferred.NewMinter(deferred.MinterOptions{}); err == nil {
		t.Fatal("expected a minter without a problem factory to be rejected")
	}

	cases := []struct {
		name    string
		options deferred.MinterOptions
	}{
		{name: "no store", options: deferred.MinterOptions{Problems: problems, Provider: provider, Clock: clock}},
		{name: "no provider", options: deferred.MinterOptions{Problems: problems, Store: store, Clock: clock}},
		{name: "no clock", options: deferred.MinterOptions{Problems: problems, Store: store, Provider: provider}},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			_, err := deferred.NewMinter(testCase.options)
			requireProblem(t, err, authengine.ProblemConfigInvalid)
		})
	}
}

func TestMintIssuesAFifteenMinuteNonceStoredOnlyAsADigest(t *testing.T) {
	t.Parallel()

	fixture := newFixture(t)

	handoff, err := fixture.minter.Mint(context.Background(), session(), nil)
	requireNoError(t, err)

	if handoff.Token == "" {
		t.Fatal("expected a minted nonce")
	}
	want := testhelper.FixedNow().Add(authengine.DeferredTokenLifetime)
	if !handoff.ExpiresAt.Equal(want) {
		t.Fatalf("expected the contract 15-minute TTL, got %s", handoff.ExpiresAt)
	}

	digests := fixture.store.Digests()
	if len(digests) != 1 || digests[0] != deferred.Digest(handoff.Token) {
		t.Fatalf("expected the nonce to be stored as a digest, got %v", digests)
	}
	if digests[0] == handoff.Token {
		t.Fatal("expected the raw nonce never to be stored")
	}
}

func TestMintRequiresAnAuthenticatedSubject(t *testing.T) {
	t.Parallel()

	_, err := newFixture(t).minter.Mint(context.Background(), authengine.Session{}, nil)
	requireProblem(t, err, authengine.ProblemTokenClaimMissing)
}

func TestMintSurfacesStoreAndClockFailures(t *testing.T) {
	t.Parallel()

	fixture := newFixture(t)
	fixture.store.EnqueueError(errFake)

	_, err := fixture.minter.Mint(context.Background(), session(), nil)
	requireProblem(t, err, authengine.ProblemProviderUnavailable)

	fixture.clock.EnqueueClockResult(time.Time{}, errFake)
	_, err = fixture.minter.Mint(context.Background(), session(), nil)
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestExchangeRedeemsExactlyOnce(t *testing.T) {
	t.Parallel()

	fixture := newFixture(t)
	ctx := context.Background()
	email := "owner@example.invalid"

	handoff, err := fixture.minter.Mint(ctx, session(), &email)
	requireNoError(t, err)

	token, err := fixture.minter.Exchange(ctx, handoff.Token)
	requireNoError(t, err)

	if token.Value == "" {
		t.Fatal("expected a one-time login token")
	}
	// The provider token is minted at REDEEM time and carries the 120-second
	// contract lifetime, not the nonce's fifteen minutes.
	if got := token.ExpiresAt.Sub(testhelper.FixedNow()); got != authengine.OneTimeTokenLifetime {
		t.Fatalf("expected the 120-second one-time lifetime, got %s", got)
	}
	calls := fixture.provider.OneTimeTokenCalls()
	if len(calls) != 1 || calls[0].Subject != "user-1" || calls[0].Email == nil {
		t.Fatalf("expected the bound identity to reach the provider, got %+v", calls)
	}

	// A replay is its own problem: a broken carrier, a double tap, and a slow
	// install are three different messages to a client.
	requireProblem(t, secondErr(fixture.minter.Exchange(ctx, handoff.Token)),
		authengine.ProblemDeferredTokenConsumed)
}

func TestExchangeRejectsAnUnknownOrBlankNonce(t *testing.T) {
	t.Parallel()

	fixture := newFixture(t)
	ctx := context.Background()

	requireProblem(t, secondErr(fixture.minter.Exchange(ctx, "")),
		authengine.ProblemDeferredTokenUnknown)
	requireProblem(t, secondErr(fixture.minter.Exchange(ctx, "never-minted")),
		authengine.ProblemDeferredTokenUnknown)
}

func TestExchangeRejectsAnExpiredNonce(t *testing.T) {
	t.Parallel()

	fixture := newFixture(t)
	ctx := context.Background()

	handoff, err := fixture.minter.Mint(ctx, session(), nil)
	requireNoError(t, err)

	fixture.clock.SetNow(testhelper.FixedNow().Add(authengine.DeferredTokenLifetime + time.Second))

	requireProblem(t, secondErr(fixture.minter.Exchange(ctx, handoff.Token)),
		authengine.ProblemDeferredTokenExpired)
	if len(fixture.provider.OneTimeTokenCalls()) != 0 {
		t.Fatal("expected an expired nonce never to reach the provider")
	}
}

func TestExchangeSurfacesStoreClockAndProviderFailures(t *testing.T) {
	t.Parallel()

	ctx := context.Background()

	t.Run("store failure", func(t *testing.T) {
		t.Parallel()

		fixture := newFixture(t)
		fixture.store.EnqueueError(errFake)
		requireProblem(t, secondErr(fixture.minter.Exchange(ctx, "anything")),
			authengine.ProblemProviderUnavailable)
	})

	t.Run("clock failure", func(t *testing.T) {
		t.Parallel()

		fixture := newFixture(t)
		fixture.clock.EnqueueClockResult(time.Time{}, errFake)
		requireProblem(t, secondErr(fixture.minter.Exchange(ctx, "anything")),
			authengine.ProblemProviderUnavailable)
	})

	t.Run("provider failure", func(t *testing.T) {
		t.Parallel()

		fixture := newFixture(t)
		handoff, err := fixture.minter.Mint(ctx, session(), nil)
		requireNoError(t, err)
		fixture.provider.EnqueueOneTimeTokenError(errFake)

		if _, err := fixture.minter.Exchange(ctx, handoff.Token); err == nil {
			t.Fatal("expected the provider failure to surface")
		}
	})
}

func TestMinterHonoursALifetimeOverride(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	minter, err := deferred.NewMinter(deferred.MinterOptions{
		Store:    testhelper.NewMemoryDeferredStore(),
		Provider: testhelper.NewFakeProvider(testhelper.FakeProviderOptions{}),
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
		Lifetime: time.Minute,
	})
	requireNoError(t, err)

	handoff, err := minter.Mint(context.Background(), session(), nil)
	requireNoError(t, err)
	if got := handoff.ExpiresAt.Sub(testhelper.FixedNow()); got != time.Minute {
		t.Fatalf("expected the overridden lifetime, got %s", got)
	}
}

func TestNonceIsFreshAndDigestIsStable(t *testing.T) {
	t.Parallel()

	first, again := deferred.Nonce(), deferred.Nonce()
	if first == again || first == "" {
		t.Fatalf("expected two distinct non-empty nonces, got %q and %q", first, again)
	}
	stable := deferred.Digest(first)
	if deferred.Digest(first) != stable {
		t.Fatal("expected the digest to be stable")
	}
	if deferred.Digest(first) == deferred.Digest(again) {
		t.Fatal("expected distinct nonces to digest differently")
	}
	if deferred.Digest(first) == first {
		t.Fatal("expected the digest not to be the nonce itself")
	}
}

// secondErr returns the error half of a (T, error) result.
func secondErr[Value any](_ Value, err error) error {
	return err
}
