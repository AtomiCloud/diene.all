package operator_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	"github.com/stretchr/testify/require"
)

// fakeStore is an in-memory ledger.Store with injectable errors. It is a test
// double only and is excluded from coverage (coverage is scoped to ./lib/...).
type fakeStore struct {
	entries map[string]ledger.Entry
	getErr  error
	putErr  error
}

func newFakeStore() *fakeStore { return &fakeStore{entries: map[string]ledger.Entry{}} }

func (s *fakeStore) Get(_ context.Context, key string) (ledger.Entry, bool, error) {
	if s.getErr != nil {
		return ledger.Entry{}, false, s.getErr
	}
	e, ok := s.entries[key]
	return e, ok, nil
}

func (s *fakeStore) Put(_ context.Context, e ledger.Entry) error {
	if s.putErr != nil {
		return s.putErr
	}
	s.entries[e.Coordinate.Key()] = e
	return nil
}

func coord() ledger.Coordinate {
	return ledger.Coordinate{Platform: "diene", Landscape: "lapras", Class: "note", Module: "sample"}
}

func TestCoordinateKey(t *testing.T) {
	require.Equal(t, "diene/lapras/note/sample", coord().Key())
}

func TestReserveCreatesIntent(t *testing.T) {
	svc := ledger.NewService(newFakeStore())
	e, err := svc.Reserve(context.Background(), coord(), "ext-1", "secret/path")
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseIntent, e.Phase)
	require.Equal(t, "ext-1", e.ExternalID)
	require.Equal(t, "secret/path", e.SecretPath)
}

func TestReserveAdoptsBackExisting(t *testing.T) {
	store := newFakeStore()
	svc := ledger.NewService(store)
	first, err := svc.Reserve(context.Background(), coord(), "ext-1", "secret/path")
	require.NoError(t, err)
	// A second reserve must adopt back, never duplicate-create.
	again, err := svc.Reserve(context.Background(), coord(), "ext-2", "other/path")
	require.NoError(t, err)
	require.Equal(t, first, again)
	require.Equal(t, "ext-1", again.ExternalID)
}

func TestReserveGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	svc := ledger.NewService(store)
	_, err := svc.Reserve(context.Background(), coord(), "e", "s")
	require.Error(t, err)
}

func TestReservePutError(t *testing.T) {
	store := newFakeStore()
	store.putErr = errors.New("boom")
	svc := ledger.NewService(store)
	_, err := svc.Reserve(context.Background(), coord(), "e", "s")
	require.Error(t, err)
}

func TestAdvanceThroughPhases(t *testing.T) {
	store := newFakeStore()
	svc := ledger.NewService(store)
	_, err := svc.Reserve(context.Background(), coord(), "e", "s")
	require.NoError(t, err)

	e, ok, err := svc.Advance(context.Background(), coord())
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, ledger.PhaseCreated, e.Phase)

	e, ok, err = svc.Advance(context.Background(), coord())
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, ledger.PhaseConfirmed, e.Phase)

	// Confirmed is terminal: next() holds it steady.
	e, ok, err = svc.Advance(context.Background(), coord())
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, ledger.PhaseConfirmed, e.Phase)
}

func TestAdvanceMissingIsNoOp(t *testing.T) {
	svc := ledger.NewService(newFakeStore())
	_, ok, err := svc.Advance(context.Background(), coord())
	require.NoError(t, err)
	require.False(t, ok)
}

func TestAdvanceGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	svc := ledger.NewService(store)
	_, _, err := svc.Advance(context.Background(), coord())
	require.Error(t, err)
}

func TestAdvancePutError(t *testing.T) {
	store := newFakeStore()
	svc := ledger.NewService(store)
	_, err := svc.Reserve(context.Background(), coord(), "e", "s")
	require.NoError(t, err)
	store.putErr = errors.New("boom")
	_, _, err = svc.Advance(context.Background(), coord())
	require.Error(t, err)
}

func TestOrphanMarksOrphaned(t *testing.T) {
	store := newFakeStore()
	svc := ledger.NewService(store)
	_, err := svc.Reserve(context.Background(), coord(), "e", "s")
	require.NoError(t, err)
	require.NoError(t, svc.Orphan(context.Background(), coord()))
	e, ok, err := store.Get(context.Background(), coord().Key())
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, ledger.PhaseOrphaned, e.Phase)
}

func TestOrphanMissingIsNoOp(t *testing.T) {
	svc := ledger.NewService(newFakeStore())
	require.NoError(t, svc.Orphan(context.Background(), coord()))
}

func TestOrphanGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	svc := ledger.NewService(store)
	require.Error(t, svc.Orphan(context.Background(), coord()))
}
