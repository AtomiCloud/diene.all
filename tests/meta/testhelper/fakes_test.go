package testhelper_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/deferred"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// errScripted is the failure the fakes' queues raise.
var errScripted = errors.New("scripted failure")

// timeUTC returns the UTC location, kept in one place so the fixture assertions
// read the same way everywhere.
func timeUTC() *time.Location {
	return time.UTC
}

// requireNoError fails the test when err is non-nil.
func requireNoError(t *testing.T, err error) {
	t.Helper()

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestFakeIDPSignsTokensItsOwnValidatorAccepts(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)

	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{
		Subject:       "user-7",
		Username:      "owner",
		Email:         "owner@example.invalid",
		Roles:         []string{"admin"},
		Scopes:        []string{"read:booking"},
		HomeLandscape: "lapras",
		Registered:    []string{"alcohol-zinc"},
		Claims:        map[string]any{"tenant": "acme"},
	})
	requireNoError(t, err)

	// Contract parity: the fake is only useful if what it mints is what the real
	// validator accepts, claim for claim.
	principal, err := validator.Validate(context.Background(), token)
	requireNoError(t, err)

	if principal.Subject != "user-7" || !principal.HasRole("admin") || !principal.HasScope("read:booking") {
		t.Fatalf("expected the requested claims to survive signing, got %+v", principal)
	}
	if principal.Username == nil || principal.Email == nil || !principal.EmailVerified {
		t.Fatalf("expected the identity claims to survive, got %+v", principal)
	}
	if principal.HomeLandscape == nil || *principal.HomeLandscape != "lapras" {
		t.Fatalf("expected the home landscape to survive, got %v", principal.HomeLandscape)
	}
	if !principal.Registered("alcohol-zinc") {
		t.Fatal("expected the registration claim to survive")
	}
	if value, _ := principal.Claims.Text("tenant"); value != "acme" {
		t.Fatalf("expected extra claims to survive, got %q", value)
	}
}

func TestFakeIDPHonoursItsOverrides(t *testing.T) {
	t.Parallel()

	moment := time.Date(2030, time.March, 3, 3, 0, 0, 0, time.UTC)
	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{
		Issuer: "https://tenant.invalid", Audience: "other", KeyID: "k9", Now: moment,
	})
	requireNoError(t, err)

	if idp.Issuer() != "https://tenant.invalid" || idp.Audience() != "other" {
		t.Fatalf("expected the configured identity, got %q / %q", idp.Issuer(), idp.Audience())
	}
	now, err := idp.Clock().NowUTC()
	requireNoError(t, err)
	if !now.Equal(moment) {
		t.Fatalf("expected the configured instant, got %s", now)
	}

	validator, err := idp.Validator()
	requireNoError(t, err)
	token, err := idp.MintAccessToken(testhelper.TokenRequest{})
	requireNoError(t, err)
	if _, err := validator.Validate(context.Background(), token); err != nil {
		t.Fatalf("expected the overridden tenant to validate itself, got %v", err)
	}
}

func TestFakeIDPHonoursACustomPortal(t *testing.T) {
	t.Parallel()

	portal := testhelper.SampleErrorPortal()
	portal.Service = "tin"

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{Portal: &portal})
	requireNoError(t, err)

	raised := idp.Problems().Raise(authengine.ProblemTokenExpired, "expired", nil)
	envelope, failure := testhelper.CheckAuthProblem(raised, authengine.ProblemTokenExpired)
	if failure != nil {
		t.Fatalf("%v", failure)
	}
	if !containsText(envelope.Type, "/tin/") {
		t.Fatalf("expected the custom portal in the type URI, got %q", envelope.Type)
	}
}

func TestFakeIDPFailureHooksReachTheUnhappyPaths(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)
	validator, err := idp.Validator()
	requireNoError(t, err)
	ctx := context.Background()

	cases := []struct {
		name    string
		request testhelper.TokenRequest
	}{
		{name: "untrusted issuer", request: testhelper.TokenRequest{Issuer: "https://evil.invalid"}},
		{name: "wrong audience", request: testhelper.TokenRequest{Audience: "other"}},
		{name: "unknown key", request: testhelper.TokenRequest{KeyID: "gone"}},
		{name: "no key id", request: testhelper.TokenRequest{OmitKeyID: true}},
		{name: "no expiry", request: testhelper.TokenRequest{OmitExpiry: true}},
		{
			name:    "already expired",
			request: testhelper.TokenRequest{ExpiresAt: testhelper.FixedNow().Add(-time.Hour)},
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			token, err := idp.MintAccessToken(testCase.request)
			requireNoError(t, err)
			if _, err := validator.Validate(ctx, token); err == nil {
				t.Fatal("expected the scripted defect to be rejected")
			}
		})
	}
}

func TestFakeIDPUnverifiedEmailIsScriptable(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)
	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{
		Email: "owner@example.invalid", EmailUnverified: true,
	})
	requireNoError(t, err)

	principal, err := validator.Validate(context.Background(), token)
	requireNoError(t, err)
	if principal.EmailVerified {
		t.Fatal("expected the unverified-email script to be honoured")
	}
}

func TestFakeIDPAdvanceCrossesTheExpiryBoundary(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)
	validator, err := idp.Validator()
	requireNoError(t, err)
	ctx := context.Background()

	token, err := idp.MintAccessToken(testhelper.TokenRequest{})
	requireNoError(t, err)
	if _, err := validator.Validate(ctx, token); err != nil {
		t.Fatalf("expected a fresh token to validate, got %v", err)
	}

	// Advancing rather than sleeping is what makes an expiry test instant.
	idp.Advance(authengine.AccessTokenLifetime + authengine.DefaultClockSkew + time.Second)
	if _, err := validator.Validate(ctx, token); err == nil {
		t.Fatal("expected the advanced clock to expire the token")
	}
}

func TestFakeIDPMintsIDTokensForADifferentAudience(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)
	validator, err := idp.Validator()
	requireNoError(t, err)
	ctx := context.Background()

	identity, err := idp.MintIDToken(testhelper.TokenRequest{Subject: "user-1"})
	requireNoError(t, err)

	if _, rejected := validator.Validate(ctx, identity); rejected == nil {
		t.Fatal("expected an ID token to fail the access-token audience check")
	}
	if _, accepted := validator.ValidateIDToken(ctx, identity); accepted != nil {
		t.Fatal("expected the ID-token path to accept it")
	}

	explicit, err := idp.MintIDToken(testhelper.TokenRequest{Audience: idp.Audience()})
	requireNoError(t, err)
	if _, err := validator.Validate(ctx, explicit); err != nil {
		t.Fatalf("expected an explicit audience override to be honoured, got %v", err)
	}
}

func TestFakeIDPGuardSharesItsPortal(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)

	guard, err := idp.Guard()
	requireNoError(t, err)

	owner := authengine.NewClaimMapper().Map(authengine.Claims{authengine.ClaimSubject: "user-1"})
	requireNoError(t, guard.Sub(owner, new("user-1")))

	double := &recorder{}
	testhelper.AssertOwnershipDenied(double, guard.Sub(owner, new("user-2")))
	if double.failed() {
		t.Fatalf("expected the shared portal to produce a matchable denial, got %q", double.message())
	}
}

func TestFakeIDPClockFailuresPropagate(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)

	idp.Clock().EnqueueClockResult(time.Time{}, errScripted)
	if _, err := idp.MintAccessToken(testhelper.TokenRequest{}); err == nil {
		t.Fatal("expected a clock failure to reach the caller")
	}
}

func TestFakeProviderRecordsAndScriptsEveryOperation(t *testing.T) {
	t.Parallel()

	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	ctx := context.Background()
	resource := authengine.Resource{Name: "alcohol-zinc", Indicator: "https://api.zinc.invalid"}

	first, err := provider.ResourceToken(ctx, authengine.ResourceTokenRequest{
		Subject: "user-1", RefreshToken: "refresh-1", Resource: resource,
	})
	requireNoError(t, err)
	second, err := provider.ClientCredentials(ctx, authengine.ClientCredentialsRequest{Resource: resource})
	requireNoError(t, err)

	// Distinct values per mint are what let a single-flight test count mints.
	if first.Value == second.Value {
		t.Fatalf("expected distinct minted tokens, got %q twice", first.Value)
	}
	if provider.Minted() != 2 {
		t.Fatalf("expected two mints, got %d", provider.Minted())
	}
	if len(provider.ResourceTokenCalls()) != 1 || len(provider.ClientCredentialsCalls()) != 1 {
		t.Fatal("expected each call to be recorded on its own ledger")
	}

	session, err := provider.Refresh(ctx, "refresh-1")
	requireNoError(t, err)
	if session.RefreshToken == "refresh-1" {
		t.Fatal("expected the default fake to rotate")
	}
	if len(provider.RefreshCalls()) != 1 || provider.RefreshCalls()[0] != "refresh-1" {
		t.Fatalf("expected the presented token to be recorded, got %v", provider.RefreshCalls())
	}

	minted, err := provider.MintOneTimeToken(ctx, authengine.OneTimeTokenRequest{Subject: "user-1"})
	requireNoError(t, err)
	if minted.Value == "" || len(provider.OneTimeTokenCalls()) != 1 {
		t.Fatalf("expected a recorded one-time token, got %+v", minted)
	}

	requireNoError(t, provider.SetClaim(ctx, "user-1", "alcohol_zinc", "true"))
	claims := provider.ClaimCalls()
	if len(claims) != 1 || claims[0].Subject != "user-1" || claims[0].Value != "true" {
		t.Fatalf("expected the claim write-back to be recorded, got %+v", claims)
	}
}

func TestFakeProviderScriptsEveryFailure(t *testing.T) {
	t.Parallel()

	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	ctx := context.Background()

	provider.EnqueueResourceTokenError(errScripted)
	provider.EnqueueClientCredentialsError(errScripted)
	provider.EnqueueRefreshError(errScripted)
	provider.EnqueueOneTimeTokenError(errScripted)
	provider.EnqueueClaimError(errScripted)

	if _, err := provider.ResourceToken(ctx, authengine.ResourceTokenRequest{}); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted resource failure, got %v", err)
	}
	if _, err := provider.ClientCredentials(ctx, authengine.ClientCredentialsRequest{}); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted client failure, got %v", err)
	}
	if _, err := provider.Refresh(ctx, "r"); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted refresh failure, got %v", err)
	}
	if _, err := provider.MintOneTimeToken(ctx, authengine.OneTimeTokenRequest{}); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted one-time failure, got %v", err)
	}
	if err := provider.SetClaim(ctx, "user-1", "c", "true"); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted claim failure, got %v", err)
	}

	// The queue is one-shot: the next call succeeds, which is what lets a test
	// script "fails once, then recovers".
	if _, err := provider.Refresh(ctx, "r"); err != nil {
		t.Fatalf("expected the queue to be exhausted, got %v", err)
	}
	if !errors.Is(testhelper.ErrFakeProvider, testhelper.ErrFakeProvider) {
		t.Fatal("expected the exported fake error to be usable")
	}
}

func TestFakeProviderCanRefuseToRotate(t *testing.T) {
	t.Parallel()

	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{
		NoRotation: true, Now: testhelper.FixedNow(),
	})

	session, err := provider.Refresh(context.Background(), "refresh-1")
	requireNoError(t, err)
	if session.RefreshToken != "refresh-1" {
		t.Fatalf("expected a non-rotating provider to return the same token, got %q", session.RefreshToken)
	}
}

func TestMemoryTokenStoreHonoursTheStoreContract(t *testing.T) {
	t.Parallel()

	store := testhelper.NewMemoryTokenStore()
	ctx := context.Background()

	// A miss is not an error: a cache built on an error-on-miss store gets this
	// subtly wrong.
	_, found, err := store.Get(ctx, "absent")
	requireNoError(t, err)
	if found {
		t.Fatal("expected a miss to report absent")
	}

	requireNoError(t, store.Set(ctx, "k", authengine.AccessToken{Value: "v"}, time.Minute))
	token, found, err := store.Get(ctx, "k")
	requireNoError(t, err)
	if !found || token.Value != "v" {
		t.Fatalf("expected the stored token, got %+v (found=%t)", token, found)
	}
	if keys := store.Keys(); len(keys) != 1 || keys[0] != "k" {
		t.Fatalf("expected one key, got %v", keys)
	}

	requireNoError(t, store.Delete(ctx, "k"))
	requireNoError(t, store.Delete(ctx, "k"))
	if keys := store.Keys(); len(keys) != 0 {
		t.Fatalf("expected the entry to be gone, got %v", keys)
	}

	for range 3 {
		store.EnqueueError(errScripted)
	}
	if _, _, err := store.Get(ctx, "k"); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted read failure, got %v", err)
	}
	if err := store.Set(ctx, "k", authengine.AccessToken{}, 0); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted write failure, got %v", err)
	}
	if err := store.Delete(ctx, "k"); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted delete failure, got %v", err)
	}
}

func TestMemoryRefreshStoreHonoursTheStoreContract(t *testing.T) {
	t.Parallel()

	store := testhelper.NewMemoryRefreshStore()
	ctx := context.Background()

	_, found, err := store.Read(ctx, "absent")
	requireNoError(t, err)
	if found {
		t.Fatal("expected an unknown fingerprint to report absent")
	}

	record := authengine.RefreshRecord{Subject: "user-1", Fingerprint: "f1"}
	requireNoError(t, store.Write(ctx, record, time.Hour))
	stored, found, err := store.Read(ctx, "f1")
	requireNoError(t, err)
	if !found || stored.Subject != "user-1" {
		t.Fatalf("expected the stored record, got %+v", stored)
	}

	snapshot := store.Records()
	snapshot["f1"] = authengine.RefreshRecord{Subject: "mutated"}
	if again := store.Records(); again["f1"].Subject != "user-1" {
		t.Fatal("expected Records to return an independent snapshot")
	}

	store.EnqueueError(errScripted)
	if _, _, err := store.Read(ctx, "f1"); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted read failure, got %v", err)
	}
	store.EnqueueError(errScripted)
	if err := store.Write(ctx, record, time.Hour); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted write failure, got %v", err)
	}
}

func TestMemoryDeferredStoreConsumesAtomically(t *testing.T) {
	t.Parallel()

	store := testhelper.NewMemoryDeferredStore()
	ctx := context.Background()

	_, found, err := store.Consume(ctx, "absent")
	requireNoError(t, err)
	if found {
		t.Fatal("expected an unknown digest to report absent")
	}

	requireNoError(t, store.Put(ctx, deferred.Record{Digest: "d1", Subject: "user-1"}, time.Minute))
	if digests := store.Digests(); len(digests) != 1 || digests[0] != "d1" {
		t.Fatalf("expected one stored digest, got %v", digests)
	}

	// Consume returns the record as it was BEFORE the call: that is what makes a
	// first redemption distinguishable from a replay.
	first, found, err := store.Consume(ctx, "d1")
	requireNoError(t, err)
	if !found || first.Consumed {
		t.Fatalf("expected the pre-call record, got %+v", first)
	}
	replay, found, err := store.Consume(ctx, "d1")
	requireNoError(t, err)
	if !found || !replay.Consumed {
		t.Fatalf("expected the replay to see a consumed record, got %+v", replay)
	}

	store.EnqueueError(errScripted)
	if err := store.Put(ctx, deferred.Record{Digest: "d2"}, time.Minute); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted put failure, got %v", err)
	}
	store.EnqueueError(errScripted)
	if _, _, err := store.Consume(ctx, "d1"); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted consume failure, got %v", err)
	}
}

func TestFakeBackendModelsEveryOnboardingOutcome(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"})
	ctx := context.Background()
	token := authengine.AccessToken{Value: "t", Resource: "alcohol-zinc"}

	if backend.Name() != "alcohol-zinc" {
		t.Fatalf("expected the configured name, got %q", backend.Name())
	}

	exists, err := backend.Exists(ctx, token)
	requireNoError(t, err)
	if exists {
		t.Fatal("expected a fresh backend to hold no row")
	}

	requireNoError(t, backend.Create(ctx, token, onboard.Registration{Subject: "user-1"}))
	// Create-or-ok: registering twice must not conflict.
	requireNoError(t, backend.Create(ctx, token, onboard.Registration{Subject: "user-1"}))

	exists, err = backend.Exists(ctx, token)
	requireNoError(t, err)
	if !exists {
		t.Fatal("expected the row to exist after creation")
	}
	if len(backend.Registrations()) != 2 {
		t.Fatalf("expected both registrations to be recorded, got %d", len(backend.Registrations()))
	}
	if len(backend.Tokens()) == 0 || backend.Tokens()[0].Resource != "alcohol-zinc" {
		t.Fatalf("expected the per-resource token to be recorded, got %v", backend.Tokens())
	}

	configured, err := backend.Configured(ctx, token)
	requireNoError(t, err)
	if !configured {
		t.Fatal("expected the default fake to report itself configured")
	}

	backend.EnqueueExistsError(errScripted)
	if _, err := backend.Exists(ctx, token); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted probe failure, got %v", err)
	}
	backend.EnqueueCreateError(errScripted)
	if err := backend.Create(ctx, token, onboard.Registration{}); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted create failure, got %v", err)
	}
	backend.EnqueueConfiguredError(errScripted)
	if _, err := backend.Configured(ctx, token); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted configuration failure, got %v", err)
	}
}

func TestFakeBackendStartsExistingOrUnconfigured(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	token := authengine.AccessToken{}

	racing := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "z", Exists: true})
	exists, err := racing.Exists(ctx, token)
	requireNoError(t, err)
	if !exists {
		t.Fatal("expected the create-time race to be scriptable")
	}

	staged := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "z", NeedsConfiguration: true})
	configured, err := staged.Configured(ctx, token)
	requireNoError(t, err)
	if configured {
		t.Fatal("expected the outstanding second step to be scriptable")
	}
}

func TestFakeRefresherModelsClaimPropagation(t *testing.T) {
	t.Parallel()

	settled := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-1", "alcohol_zinc": "true",
	})
	pending := authengine.NewClaimMapper().Map(authengine.Claims{authengine.ClaimSubject: "user-1"})

	refresher := testhelper.NewFakeRefresher(settled)
	refresher.Enqueue(pending)
	ctx := context.Background()

	// The queue models a claim that has not propagated yet, then one that has.
	first, err := refresher.Refresh(ctx, "user-1")
	requireNoError(t, err)
	if first.Registered("alcohol-zinc") {
		t.Fatal("expected the queued unregistered principal first")
	}
	second, err := refresher.Refresh(ctx, "user-1")
	requireNoError(t, err)
	if !second.Registered("alcohol-zinc") {
		t.Fatal("expected the default registered principal once the queue drains")
	}
	if calls := refresher.Calls(); len(calls) != 2 || calls[0] != "user-1" {
		t.Fatalf("expected both refreshes to be recorded, got %v", calls)
	}

	refresher.EnqueueError(errScripted)
	if _, err := refresher.Refresh(ctx, "user-1"); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted refresh failure, got %v", err)
	}
}

func TestFakePingerScriptsLatencyAndUnreachability(t *testing.T) {
	t.Parallel()

	pinger := testhelper.NewFakePinger()
	pinger.SetLatency("lapras", 25)
	pinger.SetError("mew", errScripted)
	ctx := context.Background()

	latency, err := pinger.Ping(ctx, onboard.Landscape{Name: "lapras"})
	requireNoError(t, err)
	if latency != 25*time.Millisecond {
		t.Fatalf("expected the scripted latency, got %s", latency)
	}

	if _, err := pinger.Ping(ctx, onboard.Landscape{Name: "mew"}); !errors.Is(err, errScripted) {
		t.Fatalf("expected the scripted failure, got %v", err)
	}

	// An unscripted landscape is unreachable rather than instantly fast, so a test
	// never accidentally picks a region it forgot to configure.
	if _, err := pinger.Ping(ctx, onboard.Landscape{Name: "unscripted"}); !errors.Is(
		err, testhelper.ErrLandscapeUnreachable,
	) {
		t.Fatalf("expected an unscripted landscape to be unreachable, got %v", err)
	}
	if calls := pinger.Calls(); len(calls) != 3 {
		t.Fatalf("expected every ping to be recorded, got %v", calls)
	}
}

func TestRegistrationClaimHelpersAgreeWithTheEngine(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	requireNoError(t, err)
	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{Registered: []string{"Nitroso Tin"}})
	requireNoError(t, err)

	principal, err := validator.Validate(context.Background(), token)
	requireNoError(t, err)

	// The fake derives the claim key exactly the way the engine reads it; a fake
	// that spelled it differently would prove nothing.
	if !principal.Registered("nitroso-tin") {
		t.Fatalf("expected the derived claim to match, got %v", principal.Claims)
	}
}

// containsText reports whether haystack contains needle.
func containsText(haystack string, needle string) bool {
	for index := 0; index+len(needle) <= len(haystack); index++ {
		if haystack[index:index+len(needle)] == needle {
			return true
		}
	}
	return false
}

func TestNewFakeIDPRejectsAnUnusableConfiguration(t *testing.T) {
	t.Parallel()

	// A key size the algorithm cannot honour is a configuration mistake, and a fake
	// that silently fell back would hide it.
	if _, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{KeyBits: 8}); err == nil {
		t.Fatal("expected an unusable key size to be rejected")
	}

	// A consumer problem id that collides with an engine one must be refused here
	// exactly as the engine refuses it.
	_, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{
		ExtraProblems: []problem.Type{{
			ID: authengine.ProblemTokenExpired, Title: "Mine", Version: "v1", Status: 401,
		}},
	})
	if err == nil {
		t.Fatal("expected a colliding consumer problem to be rejected")
	}
}

func TestFakeIDPRegistersConsumerProblems(t *testing.T) {
	t.Parallel()

	idp, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{
		ExtraProblems: []problem.Type{{
			ID: "booking-locked", Title: "Booking locked", Version: "v1", Status: 409,
		}},
	})
	requireNoError(t, err)

	raised := idp.Problems().Raise("booking-locked", "locked", nil)
	if _, failure := testhelper.CheckAuthProblem(raised, "booking-locked"); failure != nil {
		t.Fatalf("%v", failure)
	}
}
