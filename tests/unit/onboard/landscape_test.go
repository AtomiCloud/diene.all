package onboard_test

import (
	"context"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
)

// candidates is a selector document: names and metadata only — no addresses and no
// issuer, which is what keeps auth configuration baked by construction.
func candidates() []onboard.Landscape {
	return []onboard.Landscape{
		{Name: "lapras", Display: "Singapore", Region: "apac", Healthy: true},
		{Name: "mew", Display: "Frankfurt", Region: "emea", Healthy: true},
		{Name: "entei", Display: "Retired", Region: "apac", Healthy: false},
	}
}

// newSelector wires a selector over the fake pinger.
func newSelector(t *testing.T, pinger *testhelper.FakePinger) onboard.Selector {
	t.Helper()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	selector, err := onboard.NewSelector(onboard.SelectorOptions{Pinger: pinger, Problems: problems})
	requireNoError(t, err)
	return selector
}

func TestNewSelectorRejectsAnIncompleteConfiguration(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	if _, missing := onboard.NewSelector(onboard.SelectorOptions{}); missing == nil {
		t.Fatal("expected a selector without a problem factory to be rejected")
	}
	_, err = onboard.NewSelector(onboard.SelectorOptions{Problems: problems})
	if _, failure := testhelper.CheckAuthProblem(err, authengine.ProblemConfigInvalid); failure != nil {
		t.Fatalf("%v", failure)
	}
}

func TestHomeUsesThePresentClaimWithoutPinging(t *testing.T) {
	t.Parallel()

	pinger := testhelper.NewFakePinger()
	selector := newSelector(t, pinger)

	returning := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject:       "user-1",
		authengine.ClaimHomeLandscape: "mew",
	})

	home, err := selector.Home(context.Background(), returning, candidates())
	requireNoError(t, err)

	if home.Name != "mew" || home.Display != "Frankfurt" {
		t.Fatalf("expected the declared landscape, got %+v", home)
	}
	if len(pinger.Calls()) != 0 {
		t.Fatal("expected a returning caller to route straight home with no extra step")
	}
}

func TestHomeHonoursAClaimTheDocumentNoLongerLists(t *testing.T) {
	t.Parallel()

	selector := newSelector(t, testhelper.NewFakePinger())

	settled := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject:       "user-1",
		authengine.ClaimHomeLandscape: "raichu",
	})

	// A caller already homed somewhere the current document omits must keep going
	// there rather than being silently re-homed.
	home, err := selector.Home(context.Background(), settled, candidates())
	requireNoError(t, err)
	if home.Name != "raichu" {
		t.Fatalf("expected the claimed landscape to win, got %+v", home)
	}
}

func TestHomeFallsThroughToThePickerForANewCaller(t *testing.T) {
	t.Parallel()

	pinger := testhelper.NewFakePinger()
	pinger.SetLatency("lapras", 40)
	pinger.SetLatency("mew", 12)
	selector := newSelector(t, pinger)

	newUser := authengine.NewClaimMapper().Map(authengine.Claims{authengine.ClaimSubject: "user-1"})

	home, err := selector.Home(context.Background(), newUser, candidates())
	requireNoError(t, err)
	if home.Name != "mew" {
		t.Fatalf("expected the nearest landscape, got %+v", home)
	}
}

func TestPickSkipsUnhealthyAndUnreachableCandidates(t *testing.T) {
	t.Parallel()

	pinger := testhelper.NewFakePinger()
	pinger.SetLatency("lapras", 40)
	pinger.SetError("mew", errFake)
	pinger.SetLatency("entei", 1)
	selector := newSelector(t, pinger)

	home, err := selector.Pick(context.Background(), candidates())
	requireNoError(t, err)

	// entei is the fastest but unhealthy, and mew never answered: an unreachable
	// region is exactly the one a client should not call home.
	if home.Name != "lapras" {
		t.Fatalf("expected the fastest healthy reachable landscape, got %+v", home)
	}
	if calls := pinger.Calls(); len(calls) != 2 {
		t.Fatalf("expected only healthy candidates to be pinged, got %v", calls)
	}
}

func TestPickFailsWhenNothingAnswers(t *testing.T) {
	t.Parallel()

	pinger := testhelper.NewFakePinger()
	pinger.SetError("lapras", errFake)
	pinger.SetError("mew", errFake)
	selector := newSelector(t, pinger)

	// Guessing a home region is worse than telling the caller to retry.
	_, err := selector.Pick(context.Background(), candidates())
	envelope, failure := testhelper.CheckAuthProblem(err, authengine.ProblemHomeLandscapeUnresolved)
	if failure != nil {
		t.Fatalf("%v", failure)
	}
	named, ok := envelope.Data["candidates"].([]string)
	if !ok || len(named) != 3 {
		t.Fatalf("expected the failure to name the candidates, got %v", envelope.Data)
	}
}

func TestPickFailsOnAnEmptyDocument(t *testing.T) {
	t.Parallel()

	_, err := newSelector(t, testhelper.NewFakePinger()).Pick(context.Background(), nil)
	if _, failure := testhelper.CheckAuthProblem(
		err, authengine.ProblemHomeLandscapeUnresolved,
	); failure != nil {
		t.Fatalf("%v", failure)
	}
}

func TestPickTreatsAnUnscriptedLandscapeAsUnreachable(t *testing.T) {
	t.Parallel()

	selector := newSelector(t, testhelper.NewFakePinger())

	_, err := selector.Pick(context.Background(), candidates())
	if _, failure := testhelper.CheckAuthProblem(
		err, authengine.ProblemHomeLandscapeUnresolved,
	); failure != nil {
		t.Fatalf("%v", failure)
	}
}

func TestClaimWritesTheHomeLandscapeBack(t *testing.T) {
	t.Parallel()

	selector := newSelector(t, testhelper.NewFakePinger())
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})

	requireNoError(t, selector.Claim(context.Background(), provider, "user-1",
		onboard.Landscape{Name: "mew"}))

	calls := provider.ClaimCalls()
	if len(calls) != 1 || calls[0].Name != authengine.ClaimHomeLandscape || calls[0].Value != "mew" {
		t.Fatalf("expected the home-landscape claim to be written, got %+v", calls)
	}
}

func TestClaimSurfacesAWriteFailureAndAMissingWriter(t *testing.T) {
	t.Parallel()

	selector := newSelector(t, testhelper.NewFakePinger())
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	provider.EnqueueClaimError(errFake)
	ctx := context.Background()

	err := selector.Claim(ctx, provider, "user-1", onboard.Landscape{Name: "mew"})
	if _, failure := testhelper.CheckAuthProblem(
		err, authengine.ProblemProviderUnavailable,
	); failure != nil {
		t.Fatalf("%v", failure)
	}

	err = selector.Claim(ctx, nil, "user-1", onboard.Landscape{Name: "mew"})
	if _, failure := testhelper.CheckAuthProblem(err, authengine.ProblemConfigInvalid); failure != nil {
		t.Fatalf("%v", failure)
	}
}

func TestPreOnboardingIsNotAPerBackendPhase(t *testing.T) {
	t.Parallel()

	// The selector resolves the home landscape BEFORE any backend exists to have a
	// phase, which is why pre-onboarding sits outside the per-backend machine.
	for _, phase := range []onboard.Phase{
		onboard.PhaseBootstrapping,
		onboard.PhaseNeedsOnboarding,
		onboard.PhaseReady,
		onboard.PhaseError,
	} {
		if phase == onboard.PhasePreOnboarding {
			t.Fatal("pre-onboarding must stay distinct from every per-backend phase")
		}
	}
	if onboard.PhasePreOnboarding == "" {
		t.Fatal("expected the pre-onboarding phase to be named")
	}
}
