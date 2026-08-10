package testhelper

import (
	"context"
	"maps"
	"sync"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/deferred"
)

// MemoryTokenStore is an in-memory [authengine.TokenStore].
//
// It is the fake a single-process consumer can also ship to production behind the
// same seam, so the contract it satisfies is the real one — including that a miss is
// (zero, false, nil) rather than an error, which is the distinction a cache built on
// an error-on-miss store gets subtly wrong.
type MemoryTokenStore struct {
	mutex   sync.Mutex
	entries map[string]authengine.AccessToken
	errors  []error
}

// NewMemoryTokenStore creates an empty token store.
func NewMemoryTokenStore() *MemoryTokenStore {
	return &MemoryTokenStore{entries: map[string]authengine.AccessToken{}}
}

// EnqueueError makes the next store operation fail with err.
func (s *MemoryTokenStore) EnqueueError(err error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.errors = append(s.errors, err)
}

// Keys returns the cached keys in sorted order.
func (s *MemoryTokenStore) Keys() []string {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return sortedKeys(s.entries)
}

// Get implements [authengine.TokenStore].
func (s *MemoryTokenStore) Get(_ context.Context, key string) (authengine.AccessToken, bool, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if err := shift(&s.errors); err != nil {
		return authengine.AccessToken{}, false, err
	}
	token, found := s.entries[key]
	return token, found, nil
}

// Set implements [authengine.TokenStore]. The TTL is recorded rather than enforced:
// expiry is the cache's own decision, made off the injected clock, and a fake that
// expired entries on a real timer would make that untestable.
func (s *MemoryTokenStore) Set(
	_ context.Context,
	key string,
	token authengine.AccessToken,
	_ time.Duration,
) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if err := shift(&s.errors); err != nil {
		return err
	}
	s.entries[key] = token
	return nil
}

// Delete implements [authengine.TokenStore].
func (s *MemoryTokenStore) Delete(_ context.Context, key string) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if err := shift(&s.errors); err != nil {
		return err
	}
	delete(s.entries, key)
	return nil
}

// MemoryRefreshStore is an in-memory [authengine.RefreshStore].
type MemoryRefreshStore struct {
	mutex   sync.Mutex
	records map[string]authengine.RefreshRecord
	errors  []error
}

// NewMemoryRefreshStore creates an empty refresh store.
func NewMemoryRefreshStore() *MemoryRefreshStore {
	return &MemoryRefreshStore{records: map[string]authengine.RefreshRecord{}}
}

// EnqueueError makes the next store operation fail with err.
func (s *MemoryRefreshStore) EnqueueError(err error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.errors = append(s.errors, err)
}

// Records returns the stored records keyed by fingerprint.
func (s *MemoryRefreshStore) Records() map[string]authengine.RefreshRecord {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	snapshot := make(map[string]authengine.RefreshRecord, len(s.records))
	maps.Copy(snapshot, s.records)
	return snapshot
}

// Read implements [authengine.RefreshStore].
func (s *MemoryRefreshStore) Read(
	_ context.Context,
	fingerprint string,
) (authengine.RefreshRecord, bool, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if err := shift(&s.errors); err != nil {
		return authengine.RefreshRecord{}, false, err
	}
	record, found := s.records[fingerprint]
	return record, found, nil
}

// Write implements [authengine.RefreshStore].
func (s *MemoryRefreshStore) Write(
	_ context.Context,
	record authengine.RefreshRecord,
	_ time.Duration,
) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if err := shift(&s.errors); err != nil {
		return err
	}
	s.records[record.Fingerprint] = record
	return nil
}

// MemoryDeferredStore is an in-memory [deferred.Store] with a genuinely atomic
// consume.
//
// The atomicity is the whole point of the fake. A test that consumes concurrently
// must see exactly one first-redemption, and a store that read-then-wrote would let
// two callers both believe they won — which is the bug a replay-rejection test
// exists to catch.
type MemoryDeferredStore struct {
	mutex   sync.Mutex
	records map[string]deferred.Record
	errors  []error
}

// NewMemoryDeferredStore creates an empty deferred-login store.
func NewMemoryDeferredStore() *MemoryDeferredStore {
	return &MemoryDeferredStore{records: map[string]deferred.Record{}}
}

// EnqueueError makes the next store operation fail with err.
func (s *MemoryDeferredStore) EnqueueError(err error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.errors = append(s.errors, err)
}

// Digests returns the stored nonce digests in sorted order.
func (s *MemoryDeferredStore) Digests() []string {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return sortedKeys(s.records)
}

// Put implements [deferred.Store].
func (s *MemoryDeferredStore) Put(_ context.Context, record deferred.Record, _ time.Duration) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if err := shift(&s.errors); err != nil {
		return err
	}
	s.records[record.Digest] = record
	return nil
}

// Consume implements [deferred.Store], returning the record as it was before the
// call and marking it consumed under one lock.
func (s *MemoryDeferredStore) Consume(_ context.Context, digest string) (deferred.Record, bool, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if err := shift(&s.errors); err != nil {
		return deferred.Record{}, false, err
	}
	record, found := s.records[digest]
	if !found {
		return deferred.Record{}, false, nil
	}
	consumed := record
	consumed.Consumed = true
	s.records[digest] = consumed
	return record, true, nil
}
