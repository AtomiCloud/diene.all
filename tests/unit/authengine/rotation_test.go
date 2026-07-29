package authengine_test

import (
	"context"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// rotationFixture is a rotator over the fake provider, store, and clock.
type rotationFixture struct {
	rotator  authengine.Rotator
	provider *testhelper.FakeProvider
	store    *testhelper.MemoryRefreshStore
	clock    *mocks.InMemorySystem
}

// newRotationFixture wires a rotator with a fresh session already issued.
func newRotationFixture(t *testing.T) rotationFixture {
	t.Helper()

	problems := newProblems(t)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	store := testhelper.NewMemoryRefreshStore()
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})

	rotator, err := authengine.NewRotator(authengine.RotatorOptions{
		Provider: provider, Store: store, Problems: problems, Clock: clock,
	})
	requireNoError(t, err)
	return rotationFixture{rotator: rotator, provider: provider, store: store, clock: clock}
}

func TestNewRotatorRejectsAnIncompleteConfiguration(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	store := testhelper.NewMemoryRefreshStore()
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{})

	if _, err := authengine.NewRotator(authengine.RotatorOptions{}); err == nil {
		t.Fatal("expected a rotator without a problem factory to be rejected")
	}

	cases := []struct {
		name    string
		options authengine.RotatorOptions
	}{
		{name: "no provider", options: authengine.RotatorOptions{Problems: problems, Store: store, Clock: clock}},
		{name: "no store", options: authengine.RotatorOptions{Problems: problems, Provider: provider, Clock: clock}},
		{name: "no clock", options: authengine.RotatorOptions{Problems: problems, Provider: provider, Store: store}},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			_, err := authengine.NewRotator(testCase.options)
			requireProblem(t, err, authengine.ProblemConfigInvalid)
		})
	}
}

func TestIssueRecordsOnlyTheFingerprint(t *testing.T) {
	t.Parallel()

	fixture := newRotationFixture(t)
	session := authengine.Session{Subject: "user-1", RefreshToken: "refresh-1"}

	requireNoError(t, fixture.rotator.Issue(context.Background(), session))

	fingerprint, err := fixture.rotator.Fingerprint("refresh-1")
	requireNoError(t, err)

	records := fixture.store.Records()
	record, found := records[fingerprint]
	if !found {
		t.Fatalf("expected a record under the fingerprint, got %v", records)
	}
	if record.Subject != "user-1" || record.Consumed {
		t.Fatalf("expected an unconsumed record for user-1, got %+v", record)
	}
	// The raw token must never appear in the store.
	if _, leaked := records["refresh-1"]; leaked {
		t.Fatal("expected the raw refresh token never to be stored")
	}
	if record.ExpiresAt.Sub(record.IssuedAt) != authengine.RefreshTokenLifetime {
		t.Fatalf("expected the family 14-day lifetime, got %s", record.ExpiresAt.Sub(record.IssuedAt))
	}
}

func TestIssueHonoursAProviderSuppliedExpiry(t *testing.T) {
	t.Parallel()

	fixture := newRotationFixture(t)
	expiry := testhelper.FixedNow().Add(48 * time.Hour)

	requireNoError(t, fixture.rotator.Issue(context.Background(), authengine.Session{
		Subject: "user-1", RefreshToken: "refresh-1", RefreshExpiresAt: expiry,
	}))

	fingerprint, err := fixture.rotator.Fingerprint("refresh-1")
	requireNoError(t, err)
	if got := fixture.store.Records()[fingerprint].ExpiresAt; !got.Equal(expiry) {
		t.Fatalf("expected the provider expiry %s, got %s", expiry, got)
	}
}

func TestRotateIssuesAReplacementAndConsumesThePresentedToken(t *testing.T) {
	t.Parallel()

	fixture := newRotationFixture(t)
	ctx := context.Background()
	requireNoError(t, fixture.rotator.Issue(ctx, authengine.Session{
		Subject: "user-1", RefreshToken: "refresh-1",
	}))

	rotated, err := fixture.rotator.Rotate(ctx, "refresh-1")
	requireNoError(t, err)

	if rotated.RefreshToken == "refresh-1" {
		t.Fatal("expected the refresh token to rotate")
	}
	if rotated.Subject != "user-1" {
		t.Fatalf("expected the subject to be carried forward, got %q", rotated.Subject)
	}

	presented, err := fixture.rotator.Fingerprint("refresh-1")
	requireNoError(t, err)
	if !fixture.store.Records()[presented].Consumed {
		t.Fatal("expected the presented token to be marked consumed")
	}

	replacement, err := fixture.rotator.Fingerprint(rotated.RefreshToken)
	requireNoError(t, err)
	if _, found := fixture.store.Records()[replacement]; !found {
		t.Fatal("expected the replacement token to be recorded")
	}
}

func TestRotateTreatsReuseAsTheft(t *testing.T) {
	t.Parallel()

	fixture := newRotationFixture(t)
	ctx := context.Background()
	requireNoError(t, fixture.rotator.Issue(ctx, authengine.Session{
		Subject: "user-1", RefreshToken: "refresh-1",
	}))

	_, err := fixture.rotator.Rotate(ctx, "refresh-1")
	requireNoError(t, err)

	// The second presentation of an already-rotated token is its own problem, not a
	// generic expiry: "sign in again" and "your session may be compromised" are
	// different messages.
	envelope := requireProblem(t,
		second(fixture.rotator.Rotate(ctx, "refresh-1")),
		authengine.ProblemRefreshTokenReused)
	if envelope.Data["subject"] != "user-1" {
		t.Fatalf("expected the reuse report to name the subject, got %v", envelope.Data)
	}
}

func TestRotateRejectsAnUnissuedToken(t *testing.T) {
	t.Parallel()

	fixture := newRotationFixture(t)

	requireProblem(t,
		second(fixture.rotator.Rotate(context.Background(), "never-issued")),
		authengine.ProblemRefreshTokenUnknown)
}

func TestRotateRejectsAnExpiredToken(t *testing.T) {
	t.Parallel()

	fixture := newRotationFixture(t)
	ctx := context.Background()
	requireNoError(t, fixture.rotator.Issue(ctx, authengine.Session{
		Subject: "user-1", RefreshToken: "refresh-1",
	}))

	fixture.clock.SetNow(testhelper.FixedNow().Add(authengine.RefreshTokenLifetime + time.Hour))

	requireProblem(t,
		second(fixture.rotator.Rotate(ctx, "refresh-1")),
		authengine.ProblemTokenExpired)
}

func TestRotateSurfacesProviderAndStoreFailures(t *testing.T) {
	t.Parallel()

	ctx := context.Background()

	t.Run("provider failure", func(t *testing.T) {
		t.Parallel()

		fixture := newRotationFixture(t)
		requireNoError(t, fixture.rotator.Issue(ctx, authengine.Session{
			Subject: "user-1", RefreshToken: "refresh-1",
		}))
		fixture.provider.EnqueueRefreshError(errFake)

		if _, err := fixture.rotator.Rotate(ctx, "refresh-1"); err == nil {
			t.Fatal("expected the provider failure to surface")
		}
	})

	t.Run("read failure", func(t *testing.T) {
		t.Parallel()

		fixture := newRotationFixture(t)
		fixture.store.EnqueueError(errFake)

		requireProblem(t,
			second(fixture.rotator.Rotate(ctx, "refresh-1")),
			authengine.ProblemProviderUnavailable)
	})

	t.Run("consume-write failure", func(t *testing.T) {
		t.Parallel()

		fixture := newRotationFixture(t)
		requireNoError(t, fixture.rotator.Issue(ctx, authengine.Session{
			Subject: "user-1", RefreshToken: "refresh-1",
		}))
		// The read succeeds, the consume-marking write fails.
		fixture.store.EnqueueError(nil)
		fixture.store.EnqueueError(errFake)

		requireProblem(t,
			second(fixture.rotator.Rotate(ctx, "refresh-1")),
			authengine.ProblemProviderUnavailable)
	})

	t.Run("issue-write failure", func(t *testing.T) {
		t.Parallel()

		fixture := newRotationFixture(t)
		requireNoError(t, fixture.rotator.Issue(ctx, authengine.Session{
			Subject: "user-1", RefreshToken: "refresh-1",
		}))
		// Read, consume-write, then the replacement's issue-write fails.
		fixture.store.EnqueueError(nil)
		fixture.store.EnqueueError(nil)
		fixture.store.EnqueueError(errFake)

		requireProblem(t,
			second(fixture.rotator.Rotate(ctx, "refresh-1")),
			authengine.ProblemProviderUnavailable)
	})

	t.Run("issue store failure", func(t *testing.T) {
		t.Parallel()

		fixture := newRotationFixture(t)
		fixture.store.EnqueueError(errFake)

		requireProblem(t,
			fixture.rotator.Issue(ctx, authengine.Session{Subject: "user-1", RefreshToken: "refresh-1"}),
			authengine.ProblemProviderUnavailable)
	})
}

func TestRotateSurfacesClockFailures(t *testing.T) {
	t.Parallel()

	ctx := context.Background()

	t.Run("rotate", func(t *testing.T) {
		t.Parallel()

		fixture := newRotationFixture(t)
		fixture.clock.EnqueueClockResult(time.Time{}, errFake)

		requireProblem(t,
			second(fixture.rotator.Rotate(ctx, "refresh-1")),
			authengine.ProblemProviderUnavailable)
	})

	t.Run("issue", func(t *testing.T) {
		t.Parallel()

		fixture := newRotationFixture(t)
		fixture.clock.EnqueueClockResult(time.Time{}, errFake)

		requireProblem(t,
			fixture.rotator.Issue(ctx, authengine.Session{Subject: "user-1", RefreshToken: "refresh-1"}),
			authengine.ProblemProviderUnavailable)
	})
}

func TestRotateBackfillsASubjectlessProviderSession(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	store := testhelper.NewMemoryRefreshStore()
	rotator, err := authengine.NewRotator(authengine.RotatorOptions{
		Provider: provider,
		Store:    store,
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
		Lifetime: time.Hour,
	})
	requireNoError(t, err)

	ctx := context.Background()
	requireNoError(t, rotator.Issue(ctx, authengine.Session{Subject: "user-1", RefreshToken: "refresh-1"}))

	// The fake provider returns no subject on Refresh, mirroring a provider whose
	// token response omits it; the recorded session's subject must be carried over or
	// the replacement record would be filed against nobody.
	rotated, err := rotator.Rotate(ctx, "refresh-1")
	requireNoError(t, err)
	if rotated.Subject != "user-1" {
		t.Fatalf("expected the subject to be backfilled, got %q", rotated.Subject)
	}
}

func TestFingerprintRefusesABlankToken(t *testing.T) {
	t.Parallel()

	_, err := newRotationFixture(t).rotator.Fingerprint("")
	requireProblem(t, err, authengine.ProblemRefreshTokenUnknown)
}

func TestFingerprintIsStableAndDistinct(t *testing.T) {
	t.Parallel()

	rotator := newRotationFixture(t).rotator

	first, err := rotator.Fingerprint("refresh-1")
	requireNoError(t, err)
	again, err := rotator.Fingerprint("refresh-1")
	requireNoError(t, err)
	other, err := rotator.Fingerprint("refresh-2")
	requireNoError(t, err)

	if first != again {
		t.Fatal("expected the fingerprint to be stable")
	}
	if first == other {
		t.Fatal("expected different tokens to fingerprint differently")
	}
	if first == "refresh-1" {
		t.Fatal("expected the fingerprint not to be the token itself")
	}
}

// second returns the error half of a (T, error) result.
func second[Value any](_ Value, err error) error {
	return err
}

func TestRotationRefusesABlankTokenOnBothPaths(t *testing.T) {
	t.Parallel()

	fixture := newRotationFixture(t)
	ctx := context.Background()

	requireProblem(t,
		fixture.rotator.Issue(ctx, authengine.Session{Subject: "user-1"}),
		authengine.ProblemRefreshTokenUnknown)
	requireProblem(t,
		second(fixture.rotator.Rotate(ctx, "")),
		authengine.ProblemRefreshTokenUnknown)
}
