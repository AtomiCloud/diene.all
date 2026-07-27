package operator_test

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
)

var fixedInstant = time.Date(2026, time.July, 27, 8, 9, 10, 123456789, time.FixedZone("UTC+2", 2*60*60))

// fakeStore is an in-memory implementation of both the ordinary and explicitly
// destructive ports. Coverage is scoped to ./lib/... and excludes this test fake.
type fakeStore struct {
	entries  map[string]ledger.Entry
	getErr   error
	putErr   error
	purgeErr error
	gets     int
	puts     int
	purges   int
	lastGet  string
}

var (
	_ ledger.Store      = (*fakeStore)(nil)
	_ ledger.PurgeStore = (*fakeStore)(nil)
)

func newFakeStore() *fakeStore {
	return &fakeStore{entries: map[string]ledger.Entry{}}
}

func (s *fakeStore) Get(_ context.Context, key string) (ledger.Entry, bool, error) {
	s.gets++
	s.lastGet = key
	if s.getErr != nil {
		return ledger.Entry{}, false, s.getErr
	}
	entry, found := s.entries[key]
	return entry, found, nil
}

func (s *fakeStore) Put(_ context.Context, entry ledger.Entry) error {
	s.puts++
	if s.putErr != nil {
		return s.putErr
	}
	s.entries[entry.Coordinate.Key()] = entry
	return nil
}

func (s *fakeStore) Purge(_ context.Context, key string) error {
	s.purges++
	if s.purgeErr != nil {
		return s.purgeErr
	}
	delete(s.entries, key)
	return nil
}

func coordinate() ledger.Coordinate {
	return ledger.Coordinate{
		Platform: "diene", Landscape: "lapras", Class: "postgres", Module: "primary",
		Vendor: "neon", Account: "production-a",
	}
}

func entryAt(phase ledger.Phase) ledger.Entry {
	coordinate := coordinate()
	// #nosec G101 -- SecretPath is a non-secret pointer fixture, never a credential value.
	return ledger.Entry{
		Coordinate: coordinate, Phase: phase, ExternalID: "external-42",
		Vendor: coordinate.Vendor, Account: coordinate.Account, Region: "eu-central-1",
		SecretPath: "/diene/lapras/postgres/primary", Generation: 4,
		LastAppliedHash: "old-hash",
	}
}

func seed(store *fakeStore, phase ledger.Phase) {
	store.entries[coordinate().Key()] = entryAt(phase)
}

func strictService(t *testing.T, store ledger.Store, now func() time.Time) ledger.Service {
	t.Helper()
	service, err := ledger.NewStrictService(store, now)
	require.NoError(t, err)
	return service
}

func fixedClock() time.Time { return fixedInstant }

func completeTombstoneProof(t *testing.T) ledger.TombstoneProof {
	t.Helper()
	proof, err := ledger.NewTombstoneProof(true, true, true)
	require.NoError(t, err)
	return proof
}

func completePurgePermit(t *testing.T) ledger.PurgePermit {
	t.Helper()
	permit, err := ledger.NewPurgePermit(true, true, true, true)
	require.NoError(t, err)
	return permit
}

func TestCoordinateValidationAndKey(t *testing.T) {
	actual, err := ledger.NewCoordinate("diene", "lapras", "postgres", "primary", "neon", "production-a")
	require.NoError(t, err)
	require.Equal(t, coordinate(), actual)
	require.Equal(t, "diene/lapras/postgres/primary/neon/production-a", actual.Key())
	require.NoError(t, actual.Validate())

	fields := []string{"platform", "landscape", "class", "module", "vendor", "account"}
	for index, field := range fields {
		t.Run("blank_"+field, func(t *testing.T) {
			segments := []string{"diene", "lapras", "postgres", "primary", "neon", "production-a"}
			segments[index] = " \t "
			_, err := ledger.NewCoordinate(segments[0], segments[1], segments[2], segments[3], segments[4], segments[5])
			require.ErrorIs(t, err, ledger.ErrInvalidCoordinate)
			var coordinateError *ledger.CoordinateError
			require.ErrorAs(t, err, &coordinateError)
			require.Equal(t, field, coordinateError.Segment)
			require.Contains(t, err.Error(), "must be nonblank")
		})

		t.Run("slash_"+field, func(t *testing.T) {
			segments := []string{"diene", "lapras", "postgres", "primary", "neon", "production-a"}
			segments[index] = "bad/segment"
			_, err := ledger.NewCoordinate(segments[0], segments[1], segments[2], segments[3], segments[4], segments[5])
			require.ErrorIs(t, err, ledger.ErrInvalidCoordinate)
			require.Contains(t, err.Error(), "must be one path segment")
		})
	}
}

func TestTimestampCodecPreservesUTCNanoseconds(t *testing.T) {
	formatted, err := ledger.FormatTimestamp(fixedInstant)
	require.NoError(t, err)
	require.Equal(t, "2026-07-27T06:09:10.123456789Z", formatted)

	parsed, err := ledger.ParseTimestamp(formatted)
	require.NoError(t, err)
	require.True(t, parsed.Equal(fixedInstant))
	require.Equal(t, time.UTC, parsed.Location())

	_, err = ledger.ParseTimestamp("2026-07-27T06:09:10+02:00")
	require.ErrorIs(t, err, ledger.ErrInvalidTimestamp)
	_, err = ledger.FormatTimestamp(time.Date(0, time.January, 1, 0, 0, 0, 0, time.UTC))
	require.ErrorIs(t, err, ledger.ErrInvalidTimestamp)
}

func TestProofConstructorsRequireEveryAssertion(t *testing.T) {
	tombstoneCases := []struct {
		name                               string
		snapshotted, deleted, retainIntent bool
		message                            string
	}{
		{name: "snapshot", snapshotted: false, deleted: true, retainIntent: true, message: "snapshot"},
		{name: "vendor delete", snapshotted: true, deleted: false, retainIntent: true, message: "vendor deletion"},
		{name: "retain intent", snapshotted: true, deleted: true, retainIntent: false, message: "168h"},
	}
	for _, testCase := range tombstoneCases {
		t.Run("tombstone_"+testCase.name, func(t *testing.T) {
			_, err := ledger.NewTombstoneProof(testCase.snapshotted, testCase.deleted, testCase.retainIntent)
			require.ErrorIs(t, err, ledger.ErrInvalidTombstoneProof)
			require.Contains(t, err.Error(), testCase.message)
		})
	}
	_, err := ledger.NewTombstoneProof(true, true, true)
	require.NoError(t, err)

	purgeCases := []struct {
		name                                string
		refs, snapshot, deleted, authorized bool
		message                             string
	}{
		{name: "references", refs: false, snapshot: true, deleted: true, authorized: true, message: "references-clear"},
		{name: "snapshot", refs: true, snapshot: false, deleted: true, authorized: true, message: "snapshot"},
		{name: "externals", refs: true, snapshot: true, deleted: false, authorized: true, message: "externals-deleted"},
		{name: "authorization", refs: true, snapshot: true, deleted: true, authorized: false, message: "target authorization"},
	}
	for _, testCase := range purgeCases {
		t.Run("purge_"+testCase.name, func(t *testing.T) {
			_, actualErr := ledger.NewPurgePermit(testCase.refs, testCase.snapshot, testCase.deleted, testCase.authorized)
			require.ErrorIs(t, actualErr, ledger.ErrInvalidPurgePermit)
			require.Contains(t, actualErr.Error(), testCase.message)
		})
	}
	_, err = ledger.NewPurgePermit(true, true, true, true)
	require.NoError(t, err)
}

func TestStrictServiceConstructors(t *testing.T) {
	_, err := ledger.NewStrictService(nil, fixedClock)
	require.ErrorIs(t, err, ledger.ErrInvalidService)
	_, err = ledger.NewStrictService(newFakeStore(), nil)
	require.ErrorIs(t, err, ledger.ErrInvalidService)
	_, err = ledger.NewStrictPurgeService(nil, newFakeStore(), fixedClock)
	require.ErrorIs(t, err, ledger.ErrInvalidService)
	_, err = ledger.NewStrictPurgeService(newFakeStore(), nil, fixedClock)
	require.ErrorIs(t, err, ledger.ErrInvalidService)
	_, err = ledger.NewStrictPurgeService(newFakeStore(), newFakeStore(), fixedClock)
	require.NoError(t, err)

	_, _, err = ledger.NewService(nil).Get(context.Background(), coordinate())
	require.ErrorIs(t, err, ledger.ErrInvalidService)
}

func TestGetValidatesAndUsesTheExactKey(t *testing.T) {
	store := newFakeStore()
	seed(store, ledger.PhaseIntent)
	entry, found, err := ledger.NewService(store).Get(context.Background(), coordinate())
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, ledger.PhaseIntent, entry.Phase)
	require.Equal(t, coordinate().Key(), store.lastGet)

	store.getErr = errors.New("get failed")
	_, _, err = ledger.NewService(store).Get(context.Background(), coordinate())
	require.ErrorIs(t, err, store.getErr)

	invalid := coordinate()
	invalid.Account = ""
	getsBefore := store.gets
	_, _, err = ledger.NewService(store).Get(context.Background(), invalid)
	require.ErrorIs(t, err, ledger.ErrInvalidCoordinate)
	require.Equal(t, getsBefore, store.gets)
}

func TestIntentFacadeAndStrictIntent(t *testing.T) {
	t.Run("compatibility write keeps deterministic zero-time seam", func(t *testing.T) {
		store := newFakeStore()
		entry, err := ledger.NewService(store).Intent(context.Background(), coordinate(), "external-1", "/secret/ref")
		require.NoError(t, err)
		require.Equal(t, ledger.PhaseIntent, entry.Phase)
		require.Equal(t, coordinate().Vendor, entry.Vendor)
		require.Equal(t, coordinate().Account, entry.Account)
		require.Empty(t, entry.LastAppliedHash)
		require.Equal(t, ledger.Timestamps{}, entry.Timestamps)
	})

	t.Run("lookup first replay", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseConfirmed)
		actual, err := ledger.NewService(store).Intent(context.Background(), coordinate(), "replacement", "/other")
		require.NoError(t, err)
		require.Equal(t, "external-42", actual.ExternalID)
		require.Equal(t, 0, store.puts)
	})

	t.Run("strict full schema and stable hash", func(t *testing.T) {
		store := newFakeStore()
		service := strictService(t, store, fixedClock)
		lastApplied := map[string]any{"size": 3, "enabled": true}
		spec := ledger.IntentSpec{
			ExternalID: "external-1", Region: "eu-west-1", SecretPath: "/secret/ref",
			Generation: 7, LastApplied: lastApplied,
		}
		actual, err := service.IntentWithSpec(context.Background(), coordinate(), spec)
		require.NoError(t, err)
		expectedHash, err := coreutils.StableHash(lastApplied)
		require.NoError(t, err)
		require.Equal(t, expectedHash, actual.LastAppliedHash)
		require.Equal(t, int64(7), actual.Generation)
		require.Equal(t, "eu-west-1", actual.Region)
		require.Equal(t, "2026-07-27T06:09:10.123456789Z", actual.Timestamps.CreatedAt)
		require.Equal(t, actual.Timestamps.CreatedAt, actual.Timestamps.UpdatedAt)
	})

	t.Run("strict legacy entry point delegates to hashing engine", func(t *testing.T) {
		store := newFakeStore()
		actual, err := strictService(t, store, fixedClock).Intent(context.Background(), coordinate(), "external-1", "/secret/ref")
		require.NoError(t, err)
		require.NotEmpty(t, actual.LastAppliedHash)
		require.NotEmpty(t, actual.Timestamps.CreatedAt)
	})

	t.Run("full intent requires strict service", func(t *testing.T) {
		_, err := ledger.NewService(newFakeStore()).IntentWithSpec(context.Background(), coordinate(), validIntentSpec())
		require.ErrorIs(t, err, ledger.ErrStrictServiceRequired)
	})

	validationCases := []struct {
		name   string
		mutate func(*ledger.IntentSpec)
	}{
		{name: "external ID", mutate: func(spec *ledger.IntentSpec) { spec.ExternalID = " " }},
		{name: "secret path", mutate: func(spec *ledger.IntentSpec) { spec.SecretPath = "" }},
		{name: "generation", mutate: func(spec *ledger.IntentSpec) { spec.Generation = -1 }},
	}
	for _, testCase := range validationCases {
		t.Run("invalid_"+testCase.name, func(t *testing.T) {
			spec := validIntentSpec()
			testCase.mutate(&spec)
			_, err := strictService(t, newFakeStore(), fixedClock).IntentWithSpec(context.Background(), coordinate(), spec)
			require.ErrorIs(t, err, ledger.ErrInvalidIntent)
		})
	}

	t.Run("unhashable last applied value", func(t *testing.T) {
		spec := validIntentSpec()
		spec.LastApplied = make(chan int)
		_, err := strictService(t, newFakeStore(), fixedClock).IntentWithSpec(context.Background(), coordinate(), spec)
		require.ErrorIs(t, err, ledger.ErrInvalidIntent)
	})

	t.Run("invalid clock", func(t *testing.T) {
		service := strictService(t, newFakeStore(), func() time.Time {
			return time.Date(0, time.January, 1, 0, 0, 0, 0, time.UTC)
		})
		_, err := service.IntentWithSpec(context.Background(), coordinate(), validIntentSpec())
		require.ErrorIs(t, err, ledger.ErrInvalidTimestamp)
	})

	t.Run("store failures", func(t *testing.T) {
		getStore := newFakeStore()
		getStore.getErr = errors.New("get failed")
		_, err := ledger.NewService(getStore).Intent(context.Background(), coordinate(), "external", "/secret")
		require.ErrorIs(t, err, getStore.getErr)

		putStore := newFakeStore()
		putStore.putErr = errors.New("put failed")
		_, err = ledger.NewService(putStore).Intent(context.Background(), coordinate(), "external", "/secret")
		require.ErrorIs(t, err, putStore.putErr)
	})
}

func validIntentSpec() ledger.IntentSpec {
	return ledger.IntentSpec{
		ExternalID: "external-42", Region: "eu-central-1", SecretPath: "/secret/ref",
		Generation: 4, LastApplied: map[string]string{"size": "medium"},
	}
}

func TestStrictTransitionMatrix(t *testing.T) {
	type operation struct {
		name string
		run  func(ledger.Service, context.Context, ledger.Coordinate) (ledger.Entry, error)
	}
	operations := []operation{
		{name: "adopt", run: func(service ledger.Service, ctx context.Context, coordinate ledger.Coordinate) (ledger.Entry, error) {
			return service.Adopt(ctx, coordinate)
		}},
		{name: "created", run: func(service ledger.Service, ctx context.Context, coordinate ledger.Coordinate) (ledger.Entry, error) {
			return service.Created(ctx, coordinate)
		}},
		{name: "confirm", run: func(service ledger.Service, ctx context.Context, coordinate ledger.Coordinate) (ledger.Entry, error) {
			return service.Confirm(ctx, coordinate)
		}},
		{name: "orphan", run: func(service ledger.Service, ctx context.Context, coordinate ledger.Coordinate) (ledger.Entry, error) {
			err := service.Orphan(ctx, coordinate)
			entry := ledger.Entry{}
			if stored, found := serviceEntry(ctx, service, coordinate); found {
				entry = stored
			}
			return entry, err
		}},
	}

	unknown := ledger.Phase("future")
	cases := []struct {
		operation     string
		from          ledger.Phase
		missing       bool
		expectedPhase ledger.Phase
		expectedPuts  int
		expectedError error
	}{
		{operation: "adopt", from: ledger.PhaseIntent, expectedPhase: ledger.PhaseIntent},
		{operation: "adopt", from: ledger.PhaseCreated, expectedPhase: ledger.PhaseCreated},
		{operation: "adopt", from: ledger.PhaseConfirmed, expectedPhase: ledger.PhaseConfirmed},
		{operation: "adopt", from: ledger.PhaseOrphaned, expectedPhase: ledger.PhaseCreated, expectedPuts: 1},
		{operation: "adopt", from: ledger.PhaseTombstoned, expectedError: ledger.ErrInvalidTransition},
		{operation: "adopt", from: unknown, expectedError: ledger.ErrInvalidTransition},
		{operation: "adopt", missing: true, expectedError: ledger.ErrMissingEntry},
		{operation: "created", from: ledger.PhaseIntent, expectedPhase: ledger.PhaseCreated, expectedPuts: 1},
		{operation: "created", from: ledger.PhaseCreated, expectedPhase: ledger.PhaseCreated},
		{operation: "created", from: ledger.PhaseConfirmed, expectedPhase: ledger.PhaseConfirmed},
		{operation: "created", from: ledger.PhaseOrphaned, expectedError: ledger.ErrInvalidTransition},
		{operation: "created", from: ledger.PhaseTombstoned, expectedError: ledger.ErrInvalidTransition},
		{operation: "created", from: unknown, expectedError: ledger.ErrInvalidTransition},
		{operation: "created", missing: true, expectedError: ledger.ErrMissingEntry},
		{operation: "confirm", from: ledger.PhaseCreated, expectedPhase: ledger.PhaseConfirmed, expectedPuts: 1},
		{operation: "confirm", from: ledger.PhaseConfirmed, expectedPhase: ledger.PhaseConfirmed},
		{operation: "confirm", from: ledger.PhaseIntent, expectedError: ledger.ErrInvalidTransition},
		{operation: "confirm", from: ledger.PhaseOrphaned, expectedError: ledger.ErrInvalidTransition},
		{operation: "confirm", from: ledger.PhaseTombstoned, expectedError: ledger.ErrInvalidTransition},
		{operation: "confirm", from: unknown, expectedError: ledger.ErrInvalidTransition},
		{operation: "confirm", missing: true, expectedError: ledger.ErrMissingEntry},
		{operation: "orphan", from: ledger.PhaseIntent, expectedPhase: ledger.PhaseOrphaned, expectedPuts: 1},
		{operation: "orphan", from: ledger.PhaseCreated, expectedPhase: ledger.PhaseOrphaned, expectedPuts: 1},
		{operation: "orphan", from: ledger.PhaseConfirmed, expectedPhase: ledger.PhaseOrphaned, expectedPuts: 1},
		{operation: "orphan", from: ledger.PhaseOrphaned, expectedPhase: ledger.PhaseOrphaned},
		{operation: "orphan", from: ledger.PhaseTombstoned, expectedError: ledger.ErrInvalidTransition},
		{operation: "orphan", from: unknown, expectedError: ledger.ErrInvalidTransition},
		{operation: "orphan", missing: true},
	}

	for _, testCase := range cases {
		t.Run(testCase.operation+"_from_"+string(testCase.from), func(t *testing.T) {
			store := newFakeStore()
			if !testCase.missing {
				seed(store, testCase.from)
			}
			service := strictService(t, store, fixedClock)
			var selected operation
			for _, candidate := range operations {
				if candidate.name == testCase.operation {
					selected = candidate
				}
			}
			actual, err := selected.run(service, context.Background(), coordinate())
			if testCase.expectedError != nil {
				require.ErrorIs(t, err, testCase.expectedError)
				var transitionError *ledger.TransitionError
				require.ErrorAs(t, err, &transitionError)
				require.Contains(t, err.Error(), coordinate().Key())
				require.Contains(t, err.Error(), testCase.operation)
			} else {
				require.NoError(t, err)
				if !testCase.missing {
					require.Equal(t, testCase.expectedPhase, actual.Phase)
				}
			}
			require.Equal(t, testCase.expectedPuts, store.puts)
			if testCase.expectedPuts == 1 {
				require.Equal(t, "2026-07-27T06:09:10.123456789Z", actual.Timestamps.UpdatedAt)
				require.Equal(t, "external-42", actual.ExternalID)
				require.Equal(t, "/diene/lapras/postgres/primary", actual.SecretPath)
				if testCase.operation == "orphan" {
					require.Equal(t, actual.Timestamps.UpdatedAt, actual.Timestamps.OrphanedAt)
				}
			}
		})
	}
}

func serviceEntry(ctx context.Context, service ledger.Service, coordinate ledger.Coordinate) (ledger.Entry, bool) {
	entry, found, _ := service.Get(ctx, coordinate)
	return entry, found
}

func TestCompatibilityFacadeKeepsHistoricalLeniency(t *testing.T) {
	t.Run("valid transition keeps timestamps empty", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseIntent)
		actual, err := ledger.NewService(store).Created(context.Background(), coordinate())
		require.NoError(t, err)
		require.Equal(t, ledger.PhaseCreated, actual.Phase)
		require.Equal(t, ledger.Timestamps{}, actual.Timestamps)
	})

	for _, phase := range []ledger.Phase{ledger.PhaseOrphaned, ledger.PhaseTombstoned, ledger.Phase("future")} {
		t.Run("created_"+string(phase), func(t *testing.T) {
			store := newFakeStore()
			seed(store, phase)
			actual, err := ledger.NewService(store).Created(context.Background(), coordinate())
			require.NoError(t, err)
			require.Equal(t, phase, actual.Phase)
			require.Zero(t, store.puts)
		})
	}
	for _, phase := range []ledger.Phase{ledger.PhaseIntent, ledger.PhaseOrphaned, ledger.PhaseTombstoned, ledger.Phase("future")} {
		t.Run("confirm_"+string(phase), func(t *testing.T) {
			store := newFakeStore()
			seed(store, phase)
			actual, err := ledger.NewService(store).Confirm(context.Background(), coordinate())
			require.NoError(t, err)
			require.Equal(t, phase, actual.Phase)
			require.Zero(t, store.puts)
		})
	}
}

func TestTransitionStoreFailuresPropagate(t *testing.T) {
	type operation struct {
		name  string
		phase ledger.Phase
		run   func(ledger.Service) error
	}
	getOperations := []operation{
		{name: "adopt", run: func(service ledger.Service) error {
			_, err := service.Adopt(context.Background(), coordinate())
			return err
		}},
		{name: "created", run: func(service ledger.Service) error {
			_, err := service.Created(context.Background(), coordinate())
			return err
		}},
		{name: "confirm", run: func(service ledger.Service) error {
			_, err := service.Confirm(context.Background(), coordinate())
			return err
		}},
		{name: "orphan", run: func(service ledger.Service) error { return service.Orphan(context.Background(), coordinate()) }},
	}
	for _, operation := range getOperations {
		t.Run(operation.name+"_get", func(t *testing.T) {
			store := newFakeStore()
			store.getErr = errors.New("get failed")
			err := operation.run(strictService(t, store, fixedClock))
			require.ErrorIs(t, err, store.getErr)
		})
	}

	putOperations := []operation{
		{name: "adopt", phase: ledger.PhaseOrphaned, run: func(service ledger.Service) error {
			_, err := service.Adopt(context.Background(), coordinate())
			return err
		}},
		{name: "created", phase: ledger.PhaseIntent, run: func(service ledger.Service) error {
			_, err := service.Created(context.Background(), coordinate())
			return err
		}},
		{name: "confirm", phase: ledger.PhaseCreated, run: func(service ledger.Service) error {
			_, err := service.Confirm(context.Background(), coordinate())
			return err
		}},
		{name: "orphan", phase: ledger.PhaseConfirmed, run: func(service ledger.Service) error { return service.Orphan(context.Background(), coordinate()) }},
	}
	for _, operation := range putOperations {
		t.Run(operation.name+"_put", func(t *testing.T) {
			store := newFakeStore()
			seed(store, operation.phase)
			store.putErr = errors.New("put failed")
			err := operation.run(strictService(t, store, fixedClock))
			require.ErrorIs(t, err, store.putErr)
		})
	}

	t.Run("transition timestamp", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseIntent)
		service := strictService(t, store, func() time.Time {
			return time.Date(0, time.January, 1, 0, 0, 0, 0, time.UTC)
		})
		_, err := service.Created(context.Background(), coordinate())
		require.ErrorIs(t, err, ledger.ErrInvalidTimestamp)
		require.Zero(t, store.puts)
	})
}

func TestCrashRecoveryConvergesFromEveryIntermediatePhase(t *testing.T) {
	cases := []struct {
		name  string
		phase ledger.Phase
		run   func(t *testing.T, service ledger.Service) ledger.Entry
	}{
		{name: "intent", phase: ledger.PhaseIntent, run: func(t *testing.T, service ledger.Service) ledger.Entry {
			created, err := service.Created(context.Background(), coordinate())
			require.NoError(t, err)
			confirmed, err := service.Confirm(context.Background(), coordinate())
			require.NoError(t, err)
			require.Equal(t, ledger.PhaseCreated, created.Phase)
			return confirmed
		}},
		{name: "created", phase: ledger.PhaseCreated, run: func(t *testing.T, service ledger.Service) ledger.Entry {
			confirmed, err := service.Confirm(context.Background(), coordinate())
			require.NoError(t, err)
			return confirmed
		}},
		{name: "orphaned", phase: ledger.PhaseOrphaned, run: func(t *testing.T, service ledger.Service) ledger.Entry {
			adopted, err := service.Adopt(context.Background(), coordinate())
			require.NoError(t, err)
			require.Equal(t, ledger.PhaseCreated, adopted.Phase)
			confirmed, err := service.Confirm(context.Background(), coordinate())
			require.NoError(t, err)
			return confirmed
		}},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			store := newFakeStore()
			seed(store, testCase.phase)
			actual := testCase.run(t, strictService(t, store, fixedClock))
			require.Equal(t, ledger.PhaseConfirmed, actual.Phase)
			require.Equal(t, "external-42", actual.ExternalID)
			require.Equal(t, "/diene/lapras/postgres/primary", actual.SecretPath)
		})
	}
}

func TestAdvanceGenerationFence(t *testing.T) {
	t.Run("requires strict service", func(t *testing.T) {
		_, err := ledger.NewService(newFakeStore()).AdvanceGeneration(context.Background(), coordinate(), 1, nil)
		require.ErrorIs(t, err, ledger.ErrStrictServiceRequired)
	})

	t.Run("negative", func(t *testing.T) {
		_, err := strictService(t, newFakeStore(), fixedClock).AdvanceGeneration(context.Background(), coordinate(), -1, nil)
		require.ErrorIs(t, err, ledger.ErrInvalidIntent)
	})

	t.Run("missing", func(t *testing.T) {
		_, err := strictService(t, newFakeStore(), fixedClock).AdvanceGeneration(context.Background(), coordinate(), 5, nil)
		require.ErrorIs(t, err, ledger.ErrMissingEntry)
	})

	t.Run("lower rejected", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseConfirmed)
		_, err := strictService(t, store, fixedClock).AdvanceGeneration(context.Background(), coordinate(), 3, nil)
		require.ErrorIs(t, err, ledger.ErrStaleGeneration)
		var generationError *ledger.GenerationError
		require.ErrorAs(t, err, &generationError)
		require.Equal(t, int64(4), generationError.Stored)
		require.Contains(t, err.Error(), coordinate().Key())
		require.Zero(t, store.puts)
	})

	t.Run("equal replay", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseOrphaned)
		actual, err := strictService(t, store, fixedClock).AdvanceGeneration(context.Background(), coordinate(), 4, make(chan int))
		require.NoError(t, err)
		require.Equal(t, int64(4), actual.Generation)
		require.Zero(t, store.puts)
	})

	t.Run("higher advances", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseIntent)
		lastApplied := map[string]any{"capacity": 9}
		actual, err := strictService(t, store, fixedClock).AdvanceGeneration(context.Background(), coordinate(), 5, lastApplied)
		require.NoError(t, err)
		expectedHash, err := coreutils.StableHash(lastApplied)
		require.NoError(t, err)
		require.Equal(t, int64(5), actual.Generation)
		require.Equal(t, expectedHash, actual.LastAppliedHash)
		require.Equal(t, "2026-07-27T06:09:10.123456789Z", actual.Timestamps.UpdatedAt)
		require.Equal(t, 1, store.puts)
	})

	for _, phase := range []ledger.Phase{ledger.PhaseTombstoned, ledger.Phase("future")} {
		t.Run("invalid_phase_"+string(phase), func(t *testing.T) {
			store := newFakeStore()
			seed(store, phase)
			_, err := strictService(t, store, fixedClock).AdvanceGeneration(context.Background(), coordinate(), 5, nil)
			require.ErrorIs(t, err, ledger.ErrInvalidTransition)
		})
	}

	t.Run("hash failure", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseCreated)
		_, err := strictService(t, store, fixedClock).AdvanceGeneration(context.Background(), coordinate(), 5, make(chan int))
		require.ErrorIs(t, err, ledger.ErrInvalidIntent)
		require.Zero(t, store.puts)
	})

	t.Run("get failure", func(t *testing.T) {
		store := newFakeStore()
		store.getErr = errors.New("get failed")
		_, err := strictService(t, store, fixedClock).AdvanceGeneration(context.Background(), coordinate(), 5, nil)
		require.ErrorIs(t, err, store.getErr)
	})

	t.Run("put failure", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseConfirmed)
		store.putErr = errors.New("put failed")
		_, err := strictService(t, store, fixedClock).AdvanceGeneration(context.Background(), coordinate(), 5, nil)
		require.ErrorIs(t, err, store.putErr)
	})
}

func TestTombstoneTransitionAndRetainIntent(t *testing.T) {
	proof := completeTombstoneProof(t)
	for _, phase := range []ledger.Phase{ledger.PhaseCreated, ledger.PhaseConfirmed, ledger.PhaseOrphaned} {
		t.Run("from_"+string(phase), func(t *testing.T) {
			store := newFakeStore()
			seed(store, phase)
			actual, err := strictService(t, store, fixedClock).Tombstone(context.Background(), coordinate(), proof)
			require.NoError(t, err)
			require.Equal(t, ledger.PhaseTombstoned, actual.Phase)
			require.Equal(t, "2026-07-27T06:09:10.123456789Z", actual.Timestamps.TombstonedAt)
			require.Equal(t, actual.Timestamps.TombstonedAt, actual.Timestamps.UpdatedAt)
			require.Equal(t, "2026-08-03T06:09:10.123456789Z", actual.Timestamps.RetainUntil)
			require.Equal(t, 1, store.puts)
		})
	}

	t.Run("replay", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseTombstoned)
		actual, err := strictService(t, store, fixedClock).Tombstone(context.Background(), coordinate(), proof)
		require.NoError(t, err)
		require.Equal(t, ledger.PhaseTombstoned, actual.Phase)
		require.Zero(t, store.puts)
	})

	for _, phase := range []ledger.Phase{ledger.PhaseIntent, ledger.Phase("future")} {
		t.Run("reject_"+string(phase), func(t *testing.T) {
			store := newFakeStore()
			seed(store, phase)
			_, err := strictService(t, store, fixedClock).Tombstone(context.Background(), coordinate(), proof)
			require.ErrorIs(t, err, ledger.ErrInvalidTransition)
		})
	}

	t.Run("requires strict", func(t *testing.T) {
		_, err := ledger.NewService(newFakeStore()).Tombstone(context.Background(), coordinate(), proof)
		require.ErrorIs(t, err, ledger.ErrStrictServiceRequired)
	})

	t.Run("zero proof", func(t *testing.T) {
		_, err := strictService(t, newFakeStore(), fixedClock).Tombstone(context.Background(), coordinate(), ledger.TombstoneProof{})
		require.ErrorIs(t, err, ledger.ErrInvalidTombstoneProof)
	})

	t.Run("missing", func(t *testing.T) {
		_, err := strictService(t, newFakeStore(), fixedClock).Tombstone(context.Background(), coordinate(), proof)
		require.ErrorIs(t, err, ledger.ErrMissingEntry)
	})

	t.Run("get failure", func(t *testing.T) {
		store := newFakeStore()
		store.getErr = errors.New("get failed")
		_, err := strictService(t, store, fixedClock).Tombstone(context.Background(), coordinate(), proof)
		require.ErrorIs(t, err, store.getErr)
	})

	t.Run("clock failure", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseConfirmed)
		service := strictService(t, store, func() time.Time {
			return time.Date(0, time.January, 1, 0, 0, 0, 0, time.UTC)
		})
		_, err := service.Tombstone(context.Background(), coordinate(), proof)
		require.ErrorIs(t, err, ledger.ErrInvalidTimestamp)
	})

	t.Run("retain timestamp overflow", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseConfirmed)
		service := strictService(t, store, func() time.Time {
			return time.Date(9999, time.December, 30, 0, 0, 0, 0, time.UTC)
		})
		_, err := service.Tombstone(context.Background(), coordinate(), proof)
		require.ErrorIs(t, err, ledger.ErrInvalidTimestamp)
		require.Zero(t, store.puts)
	})

	t.Run("put failure", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseConfirmed)
		store.putErr = errors.New("put failed")
		_, err := strictService(t, store, fixedClock).Tombstone(context.Background(), coordinate(), proof)
		require.ErrorIs(t, err, store.putErr)
	})
}

func TestPurgeRequiresCapabilityAndPermit(t *testing.T) {
	permit := completePurgePermit(t)

	t.Run("authorized purge and missing replay", func(t *testing.T) {
		store := newFakeStore()
		seed(store, ledger.PhaseTombstoned)
		service, err := ledger.NewStrictPurgeService(store, store, fixedClock)
		require.NoError(t, err)
		require.NoError(t, service.Purge(context.Background(), coordinate(), permit))
		_, found := store.entries[coordinate().Key()]
		require.False(t, found)
		require.NoError(t, service.Purge(context.Background(), coordinate(), permit))
		require.Equal(t, 2, store.purges)
	})

	t.Run("zero permit", func(t *testing.T) {
		store := newFakeStore()
		service, err := ledger.NewStrictPurgeService(store, store, fixedClock)
		require.NoError(t, err)
		err = service.Purge(context.Background(), coordinate(), ledger.PurgePermit{})
		require.ErrorIs(t, err, ledger.ErrInvalidPurgePermit)
		require.Zero(t, store.purges)
	})

	t.Run("ordinary service has no capability", func(t *testing.T) {
		err := strictService(t, newFakeStore(), fixedClock).Purge(context.Background(), coordinate(), permit)
		require.ErrorIs(t, err, ledger.ErrPurgeUnavailable)
	})

	t.Run("coordinate validated before delete", func(t *testing.T) {
		store := newFakeStore()
		service, err := ledger.NewStrictPurgeService(store, store, fixedClock)
		require.NoError(t, err)
		invalid := coordinate()
		invalid.Vendor = ""
		err = service.Purge(context.Background(), invalid, permit)
		require.ErrorIs(t, err, ledger.ErrInvalidCoordinate)
		require.Zero(t, store.purges)
	})

	t.Run("backend failure", func(t *testing.T) {
		store := newFakeStore()
		store.purgeErr = errors.New("purge failed")
		service, err := ledger.NewStrictPurgeService(store, store, fixedClock)
		require.NoError(t, err)
		err = service.Purge(context.Background(), coordinate(), permit)
		require.ErrorIs(t, err, store.purgeErr)
	})
}

func TestEntrySchemaIsPointerOnlyAndAdditive(t *testing.T) {
	expectedEntryFields := map[string]string{
		"Coordinate": "coordinate", "Phase": "phase", "ExternalID": "externalId",
		"Vendor": "vendor", "Account": "account", "Region": "region",
		"SecretPath": "secretPath", "Generation": "generation",
		"LastAppliedHash": "lastAppliedHash", "Timestamps": "timestamps",
	}
	entryType := reflect.TypeFor[ledger.Entry]()
	require.Equal(t, len(expectedEntryFields), entryType.NumField())
	for field := range entryType.Fields() {
		expectedJSONName, found := expectedEntryFields[field.Name]
		require.True(t, found, "unexpected ledger field %s", field.Name)
		require.Equal(t, expectedJSONName, strings.Split(field.Tag.Get("json"), ",")[0])
		lowerName := strings.ToLower(field.Name)
		if field.Name != "SecretPath" {
			for _, forbidden := range []string{"secret", "credential", "password", "token", "connection", "payload"} {
				require.NotContains(t, lowerName, forbidden)
			}
		}
	}
	secretPathField, found := entryType.FieldByName("SecretPath")
	require.True(t, found)
	require.Equal(t, reflect.TypeFor[string](), secretPathField.Type, "SecretPath must remain a path string, not a value envelope")

	expectedTimestampFields := map[string]string{
		"CreatedAt": "createdAt", "UpdatedAt": "updatedAt", "OrphanedAt": "orphanedAt",
		"TombstonedAt": "tombstonedAt", "RetainUntil": "retainUntil",
	}
	timestampType := reflect.TypeFor[ledger.Timestamps]()
	require.Equal(t, len(expectedTimestampFields), timestampType.NumField())
	for field := range timestampType.Fields() {
		require.Equal(t, expectedTimestampFields[field.Name], strings.Split(field.Tag.Get("json"), ",")[0])
		require.Equal(t, reflect.TypeFor[string](), field.Type)
	}

	input := entryAt(ledger.PhaseConfirmed)
	input.Timestamps = ledger.Timestamps{CreatedAt: "2026-07-27T06:09:10.123456789Z"}
	encoded, err := json.Marshal(input)
	require.NoError(t, err)
	var actual ledger.Entry
	require.NoError(t, json.Unmarshal(encoded, &actual))
	require.Equal(t, input, actual)
}
