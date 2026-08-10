package authengine

import "sync"

// tokenFlight collapses concurrent duplicate mints for one cache key into a
// single call whose result every waiter observes.
//
// It is deliberately tiny and local rather than a dependency: the whole
// behaviour is "the first caller for a key does the work, the rest wait for it",
// and expressing it here keeps the token cache's contract — one mint per key per
// race — provable from this package's own tests.
type tokenFlight struct {
	mutex sync.Mutex
	calls map[string]*tokenCall
}

// tokenCall is one in-flight mint other callers may join.
type tokenCall struct {
	done  chan struct{}
	token AccessToken
	err   error
}

// newTokenFlight creates an empty flight group.
func newTokenFlight() *tokenFlight {
	return &tokenFlight{calls: map[string]*tokenCall{}}
}

// do runs mint for key unless a call for key is already in flight, in which case
// it waits for that call and returns its outcome.
func (f *tokenFlight) do(key string, mint func() (AccessToken, error)) (AccessToken, error) {
	f.mutex.Lock()
	if existing, joined := f.calls[key]; joined {
		f.mutex.Unlock()
		<-existing.done
		return existing.token, existing.err
	}
	pending := &tokenCall{done: make(chan struct{})}
	f.calls[key] = pending
	f.mutex.Unlock()

	token, err := mint()

	pending.token = token
	pending.err = err
	f.mutex.Lock()
	delete(f.calls, key)
	f.mutex.Unlock()
	close(pending.done)

	return token, err
}
