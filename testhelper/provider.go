package testhelper

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// FakeProvider is a scriptable in-memory [authengine.Provider].
//
// It records every call and lets a test enqueue the next outcome per operation,
// which is what makes the awkward cases reachable: a refresh that fails once and
// then succeeds, a claim write-back that errors after the user row was created, a
// provider that returns a token with no rotation. Recording the calls is what proves
// the single-flight cache made exactly ONE mint under concurrency.
type FakeProvider struct {
	mutex sync.Mutex

	resourceErrors []error
	refreshErrors  []error
	clientErrors   []error
	oneTimeErrors  []error
	claimErrors    []error

	resourceCalls []authengine.ResourceTokenRequest
	refreshCalls  []string
	clientCalls   []authengine.ClientCredentialsRequest
	oneTimeCalls  []authengine.OneTimeTokenRequest
	claimCalls    []ClaimCall

	minted int
	now    time.Time

	rotate bool
}

// ClaimCall records one claim write-back.
type ClaimCall struct {
	// Subject is the identity-provider user the claim was written on.
	Subject string
	// Name is the claim name.
	Name string
	// Value is the claim value.
	Value any
}

// FakeProviderOptions configures a [FakeProvider].
type FakeProviderOptions struct {
	// Now fixes the instant minted tokens are issued at. Zero uses [FixedNow].
	Now time.Time
	// NoRotation makes Refresh return no replacement refresh token, so a consumer
	// can prove it copes with a provider that does not rotate.
	NoRotation bool
}

// NewFakeProvider creates a fake provider.
func NewFakeProvider(options FakeProviderOptions) *FakeProvider {
	now := options.Now
	if now.IsZero() {
		now = FixedNow()
	}
	return &FakeProvider{now: now, rotate: !options.NoRotation}
}

// EnqueueResourceTokenError makes the next ResourceToken call fail with err.
func (p *FakeProvider) EnqueueResourceTokenError(err error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.resourceErrors = append(p.resourceErrors, err)
}

// EnqueueRefreshError makes the next Refresh call fail with err.
func (p *FakeProvider) EnqueueRefreshError(err error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.refreshErrors = append(p.refreshErrors, err)
}

// EnqueueClientCredentialsError makes the next ClientCredentials call fail with err.
func (p *FakeProvider) EnqueueClientCredentialsError(err error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.clientErrors = append(p.clientErrors, err)
}

// EnqueueOneTimeTokenError makes the next MintOneTimeToken call fail with err.
func (p *FakeProvider) EnqueueOneTimeTokenError(err error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.oneTimeErrors = append(p.oneTimeErrors, err)
}

// EnqueueClaimError makes the next SetClaim call fail with err.
func (p *FakeProvider) EnqueueClaimError(err error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.claimErrors = append(p.claimErrors, err)
}

// Minted returns how many tokens the provider has minted, which is the assertion a
// single-flight test makes.
func (p *FakeProvider) Minted() int {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return p.minted
}

// ResourceTokenCalls returns the recorded per-resource token requests.
func (p *FakeProvider) ResourceTokenCalls() []authengine.ResourceTokenRequest {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return append([]authengine.ResourceTokenRequest(nil), p.resourceCalls...)
}

// RefreshCalls returns the refresh tokens presented to Refresh.
func (p *FakeProvider) RefreshCalls() []string {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return append([]string(nil), p.refreshCalls...)
}

// ClientCredentialsCalls returns the recorded machine-to-machine requests.
func (p *FakeProvider) ClientCredentialsCalls() []authengine.ClientCredentialsRequest {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return append([]authengine.ClientCredentialsRequest(nil), p.clientCalls...)
}

// OneTimeTokenCalls returns the recorded one-time-token requests.
func (p *FakeProvider) OneTimeTokenCalls() []authengine.OneTimeTokenRequest {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return append([]authengine.OneTimeTokenRequest(nil), p.oneTimeCalls...)
}

// ClaimCalls returns the recorded claim write-backs.
func (p *FakeProvider) ClaimCalls() []ClaimCall {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return append([]ClaimCall(nil), p.claimCalls...)
}

// ResourceToken implements [authengine.Provider].
func (p *FakeProvider) ResourceToken(
	_ context.Context,
	request authengine.ResourceTokenRequest,
) (authengine.AccessToken, error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.resourceCalls = append(p.resourceCalls, request)
	if err := shift(&p.resourceErrors); err != nil {
		return authengine.AccessToken{}, err
	}
	return p.grant(request.Resource), nil
}

// ClientCredentials implements [authengine.Provider].
func (p *FakeProvider) ClientCredentials(
	_ context.Context,
	request authengine.ClientCredentialsRequest,
) (authengine.AccessToken, error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.clientCalls = append(p.clientCalls, request)
	if err := shift(&p.clientErrors); err != nil {
		return authengine.AccessToken{}, err
	}
	return p.grant(request.Resource), nil
}

// Refresh implements [authengine.Provider], rotating the refresh token unless the
// fake was built without rotation.
func (p *FakeProvider) Refresh(_ context.Context, refreshToken string) (authengine.Session, error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.refreshCalls = append(p.refreshCalls, refreshToken)
	if err := shift(&p.refreshErrors); err != nil {
		return authengine.Session{}, err
	}
	rotated := refreshToken
	if p.rotate {
		rotated = refreshToken + "-rotated"
	}
	return authengine.Session{
		Access:           p.grant(authengine.Resource{}),
		RefreshToken:     rotated,
		RefreshExpiresAt: p.now.Add(authengine.RefreshTokenLifetime),
	}, nil
}

// MintOneTimeToken implements [authengine.Provider].
func (p *FakeProvider) MintOneTimeToken(
	_ context.Context,
	request authengine.OneTimeTokenRequest,
) (authengine.OneTimeToken, error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.oneTimeCalls = append(p.oneTimeCalls, request)
	if err := shift(&p.oneTimeErrors); err != nil {
		return authengine.OneTimeToken{}, err
	}
	return authengine.OneTimeToken{
		Value:     "one-time-" + request.Subject,
		ExpiresAt: p.now.Add(authengine.OneTimeTokenLifetime),
	}, nil
}

// SetClaim implements [authengine.Provider].
func (p *FakeProvider) SetClaim(_ context.Context, subject string, name string, value any) error {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.claimCalls = append(p.claimCalls, ClaimCall{Subject: subject, Name: name, Value: value})
	return shift(&p.claimErrors)
}

// grant mints one deterministic token. The caller already holds the mutex.
func (p *FakeProvider) grant(resource authengine.Resource) authengine.AccessToken {
	p.minted++
	return authengine.AccessToken{
		Value:     "access-" + resource.Name + "-" + itoa(p.minted),
		Resource:  resource.Name,
		Scopes:    resource.Scopes,
		IssuedAt:  p.now,
		ExpiresAt: p.now.Add(authengine.AccessTokenLifetime),
	}
}

// ErrFakeProvider is the error the fake raises when a test enqueues a failure
// without supplying one of its own.
var ErrFakeProvider = errors.New("fake identity provider failure")

// shift pops the next scripted outcome from queue.
func shift(queue *[]error) error {
	if len(*queue) == 0 {
		return nil
	}
	next := (*queue)[0]
	*queue = (*queue)[1:]
	return next
}
