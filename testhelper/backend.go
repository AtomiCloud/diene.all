package testhelper

import (
	"context"
	"sync"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
)

// FakeBackend is a scriptable [onboard.Backend].
//
// Onboarding is a five-step sequence whose interesting cases are all failures at
// step three, four, or five, so this fake exists to make each of them reachable: a
// row that already exists (the first-sign-in race), a create that fails, a probe
// that fails. It records the registrations it received so a test can prove the raw
// tokens really travelled as data.
type FakeBackend struct {
	mutex sync.Mutex

	name             string
	exists           bool
	unconfigured     bool
	existsErrors     []error
	createErrors     []error
	configuredErrors []error
	registrations    []onboard.Registration
	tokens           []authengine.AccessToken
}

// FakeBackendOptions configures a [FakeBackend].
type FakeBackendOptions struct {
	// Name is the backend's resource-tree name.
	Name string
	// Exists starts the backend with a user row already present, which is the
	// concurrent-first-sign-in race.
	Exists bool
	// NeedsConfiguration makes the backend report its app-specific onboarding step
	// as outstanding, so a round settles in onboard.PhaseNeedsOnboarding.
	NeedsConfiguration bool
}

// NewFakeBackend creates a fake onboarding backend.
func NewFakeBackend(options FakeBackendOptions) *FakeBackend {
	return &FakeBackend{name: options.Name, exists: options.Exists, unconfigured: options.NeedsConfiguration}
}

// EnqueueExistsError makes the next Exists call fail with err.
func (b *FakeBackend) EnqueueExistsError(err error) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	b.existsErrors = append(b.existsErrors, err)
}

// EnqueueCreateError makes the next Create call fail with err.
func (b *FakeBackend) EnqueueCreateError(err error) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	b.createErrors = append(b.createErrors, err)
}

// Registrations returns the registrations the backend received.
func (b *FakeBackend) Registrations() []onboard.Registration {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	return append([]onboard.Registration(nil), b.registrations...)
}

// Tokens returns the access tokens the backend was called with, so a test can prove
// each backend was called with its OWN per-resource token.
func (b *FakeBackend) Tokens() []authengine.AccessToken {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	return append([]authengine.AccessToken(nil), b.tokens...)
}

// Name implements [onboard.Backend].
func (b *FakeBackend) Name() string {
	return b.name
}

// Exists implements [onboard.Backend].
func (b *FakeBackend) Exists(_ context.Context, token authengine.AccessToken) (bool, error) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	b.tokens = append(b.tokens, token)
	if err := shift(&b.existsErrors); err != nil {
		return false, err
	}
	return b.exists, nil
}

// Create implements [onboard.Backend] with create-or-ok semantics: registering an
// already-registered caller succeeds rather than conflicting.
func (b *FakeBackend) Create(
	_ context.Context,
	token authengine.AccessToken,
	registration onboard.Registration,
) error {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	b.tokens = append(b.tokens, token)
	if err := shift(&b.createErrors); err != nil {
		return err
	}
	b.registrations = append(b.registrations, registration)
	b.exists = true
	return nil
}

// FakeRefresher is a scriptable [onboard.TokenRefresher].
//
// The queue models claim propagation: a test enqueues the principal each refresh
// should observe, so it can prove that a claim which never appears is reported as a
// stalled onboarding rather than as success.
type FakeRefresher struct {
	mutex     sync.Mutex
	principal authengine.Principal
	queued    []authengine.Principal
	errors    []error
	calls     []string
}

// NewFakeRefresher creates a refresher that returns principal by default.
func NewFakeRefresher(principal authengine.Principal) *FakeRefresher {
	return &FakeRefresher{principal: principal}
}

// Enqueue makes the next Refresh call return principal.
func (r *FakeRefresher) Enqueue(principal authengine.Principal) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	r.queued = append(r.queued, principal)
}

// EnqueueError makes the next Refresh call fail with err.
func (r *FakeRefresher) EnqueueError(err error) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	r.errors = append(r.errors, err)
}

// Calls returns the subjects Refresh was called for.
func (r *FakeRefresher) Calls() []string {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	return append([]string(nil), r.calls...)
}

// Refresh implements [onboard.TokenRefresher].
func (r *FakeRefresher) Refresh(_ context.Context, subject string) (authengine.Principal, error) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	r.calls = append(r.calls, subject)
	if err := shift(&r.errors); err != nil {
		return authengine.Principal{}, err
	}
	if len(r.queued) > 0 {
		next := r.queued[0]
		r.queued = r.queued[1:]
		return next, nil
	}
	return r.principal, nil
}

// FakePinger is a scriptable [onboard.Pinger] returning fixed latencies per
// landscape name.
type FakePinger struct {
	mutex     sync.Mutex
	latencies map[string]int
	errors    map[string]error
	calls     []string
}

// NewFakePinger creates a pinger with no known landscapes.
func NewFakePinger() *FakePinger {
	return &FakePinger{latencies: map[string]int{}, errors: map[string]error{}}
}

// SetLatency makes landscape answer with the given latency in milliseconds.
func (p *FakePinger) SetLatency(landscape string, milliseconds int) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.latencies[landscape] = milliseconds
}

// SetError makes landscape fail to answer, which is how a test proves an
// unreachable region is skipped rather than chosen.
func (p *FakePinger) SetError(landscape string, err error) {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	p.errors[landscape] = err
}

// Calls returns the landscape names that were pinged.
func (p *FakePinger) Calls() []string {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return append([]string(nil), p.calls...)
}

// Configured implements [onboard.Configurable]. The fake always advertises the
// capability so a consumer can drive both settled outcomes from one type; a backend
// with no second step simply does not implement the interface.
func (b *FakeBackend) Configured(_ context.Context, token authengine.AccessToken) (bool, error) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	b.tokens = append(b.tokens, token)
	if err := shift(&b.configuredErrors); err != nil {
		return false, err
	}
	return !b.unconfigured, nil
}

// EnqueueConfiguredError makes the next Configured call fail with err.
func (b *FakeBackend) EnqueueConfiguredError(err error) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	b.configuredErrors = append(b.configuredErrors, err)
}
