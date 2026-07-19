package operator_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	"github.com/stretchr/testify/require"
)

// fakeStore is an in-memory ledger.Store with injectable errors. Excluded from
// coverage (coverage is scoped to ./lib/...).
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

func seed(store *fakeStore, phase ledger.Phase) {
	store.entries[coord().Key()] = ledger.Entry{Coordinate: coord(), Phase: phase, ExternalID: "ext-1", SecretPath: "secret/path"}
}

func TestCoordinateKey(t *testing.T) {
	require.Equal(t, "diene/lapras/note/sample", coord().Key())
}

func TestGet(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseIntent)
	e, ok, err := ledger.NewService(store).Get(context.Background(), coord())
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, ledger.PhaseIntent, e.Phase)
}

func TestIntentCreatesWhenMissing(t *testing.T) {
	svc := ledger.NewService(newFakeStore())
	e, err := svc.Intent(context.Background(), coord(), "ext-1", "secret/path")
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseIntent, e.Phase)
	require.Equal(t, "ext-1", e.ExternalID)
	require.Equal(t, "secret/path", e.SecretPath)
}

func TestIntentLookupFirst(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseConfirmed)
	e, err := ledger.NewService(store).Intent(context.Background(), coord(), "ext-2", "other")
	require.NoError(t, err)
	require.Equal(t, "ext-1", e.ExternalID) // existing preserved, never duplicate-created
	require.Equal(t, ledger.PhaseConfirmed, e.Phase)
}

func TestIntentGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	_, err := ledger.NewService(store).Intent(context.Background(), coord(), "e", "s")
	require.Error(t, err)
}

func TestIntentPutError(t *testing.T) {
	store := newFakeStore()
	store.putErr = errors.New("boom")
	_, err := ledger.NewService(store).Intent(context.Background(), coord(), "e", "s")
	require.Error(t, err)
}

func TestAdoptReactivatesOrphaned(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseOrphaned)
	e, err := ledger.NewService(store).Adopt(context.Background(), coord())
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseCreated, e.Phase)
	require.Equal(t, "ext-1", e.ExternalID) // external ID/secret preserved
	require.Equal(t, "secret/path", e.SecretPath)
}

func TestAdoptNonOrphanedUnchanged(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseConfirmed)
	e, err := ledger.NewService(store).Adopt(context.Background(), coord())
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, e.Phase)
}

func TestAdoptMissingErrors(t *testing.T) {
	_, err := ledger.NewService(newFakeStore()).Adopt(context.Background(), coord())
	require.Error(t, err)
}

func TestAdoptGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	_, err := ledger.NewService(store).Adopt(context.Background(), coord())
	require.Error(t, err)
}

func TestAdoptPutError(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseOrphaned)
	store.putErr = errors.New("boom")
	_, err := ledger.NewService(store).Adopt(context.Background(), coord())
	require.Error(t, err)
}

func TestCreatedFromIntent(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseIntent)
	e, err := ledger.NewService(store).Created(context.Background(), coord())
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseCreated, e.Phase)
}

func TestCreatedIdempotent(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseConfirmed)
	e, err := ledger.NewService(store).Created(context.Background(), coord())
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, e.Phase)
}

func TestCreatedMissingErrors(t *testing.T) {
	_, err := ledger.NewService(newFakeStore()).Created(context.Background(), coord())
	require.Error(t, err)
}

func TestCreatedGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	_, err := ledger.NewService(store).Created(context.Background(), coord())
	require.Error(t, err)
}

func TestCreatedPutError(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseIntent)
	store.putErr = errors.New("boom")
	_, err := ledger.NewService(store).Created(context.Background(), coord())
	require.Error(t, err)
}

func TestConfirm(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseCreated)
	e, err := ledger.NewService(store).Confirm(context.Background(), coord())
	require.NoError(t, err)
	require.Equal(t, ledger.PhaseConfirmed, e.Phase)
}

func TestConfirmMissingErrors(t *testing.T) {
	_, err := ledger.NewService(newFakeStore()).Confirm(context.Background(), coord())
	require.Error(t, err)
}

func TestConfirmGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	_, err := ledger.NewService(store).Confirm(context.Background(), coord())
	require.Error(t, err)
}

func TestConfirmPutError(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseCreated)
	store.putErr = errors.New("boom")
	_, err := ledger.NewService(store).Confirm(context.Background(), coord())
	require.Error(t, err)
}

func TestOrphanMarksOrphaned(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseConfirmed)
	require.NoError(t, ledger.NewService(store).Orphan(context.Background(), coord()))
	require.Equal(t, ledger.PhaseOrphaned, store.entries[coord().Key()].Phase)
}

func TestOrphanMissingNoOp(t *testing.T) {
	require.NoError(t, ledger.NewService(newFakeStore()).Orphan(context.Background(), coord()))
}

func TestOrphanGetError(t *testing.T) {
	store := newFakeStore()
	store.getErr = errors.New("boom")
	require.Error(t, ledger.NewService(store).Orphan(context.Background(), coord()))
}
