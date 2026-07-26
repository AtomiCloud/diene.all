package testhelper

import (
	"context"
	"errors"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	presetth "github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// StackOptions selects which infra presets a [Stack] boots.
//
// Nothing is booted by default. An integration test that needs Postgres should
// pay for Postgres and nothing else, because a suite that boots four containers
// to test one adapter is a suite people stop running.
type StackOptions struct {
	// Key is the connection key every started preset is emitted under. Blank
	// uses [PresetDefaultKey].
	Key string
	// Postgres boots the Postgres preset.
	Postgres bool
	// Cache boots the cache preset.
	Cache bool
	// Kv boots the kv preset.
	Kv bool
	// Storage boots the storage preset; the preset helper creates its bucket.
	Storage bool
	// Runtime overrides the container runtime. Nil uses the real Docker
	// runtime.
	Runtime PresetRuntime
}

// Stack is a booted set of infra preset containers and the configuration blocks
// that address them.
//
// This is the DB-adapter integration tier (G1) and nothing more. It boots
// DATA dependencies; it never boots telemetry infrastructure, and there is no
// fake OTLP collector here or anywhere else in this module — the otel interface
// mocks cover emission at the integration tier, and real export is a SIT concern
// against the Garden preview environment.
type Stack struct {
	// Postgres is the started Postgres preset, or nil.
	Postgres *PresetStartedPostgres
	// Cache is the started cache preset, or nil.
	Cache *PresetStartedCache
	// Kv is the started kv preset, or nil.
	Kv *PresetStartedKv
	// Storage is the started storage preset, or nil.
	Storage *PresetStartedStorage
}

// StartStack boots the selected presets and returns them together.
//
// A partial failure terminates whatever already started before returning, so a
// failed boot never leaks a container into the next test. Selecting nothing is a
// [ErrEmptyStack] rather than an empty success: a test that boots no dependency
// does not want this helper.
func StartStack(ctx context.Context, options StackOptions) (*Stack, error) {
	if !options.Postgres && !options.Cache && !options.Kv && !options.Storage {
		return nil, ErrEmptyStack
	}
	key := options.Key
	if key == "" {
		key = PresetDefaultKey
	}
	stack := &Stack{Postgres: nil, Cache: nil, Kv: nil, Storage: nil}
	if options.Postgres {
		started, err := presetth.StartPostgres(ctx, PresetPostgresOptions{
			Key: key, Image: "", Database: "", Username: "", Password: "", Runtime: options.Runtime,
		})
		if err != nil {
			return nil, stack.unwind(ctx, err)
		}
		stack.Postgres = started
	}
	if options.Cache {
		started, err := presetth.StartCache(ctx, PresetRedisOptions{
			Key: key, Image: "", DB: 0, Runtime: options.Runtime,
		})
		if err != nil {
			return nil, stack.unwind(ctx, err)
		}
		stack.Cache = started
	}
	if options.Kv {
		started, err := presetth.StartKv(ctx, PresetRedisOptions{
			Key: key, Image: "", DB: 0, Runtime: options.Runtime,
		})
		if err != nil {
			return nil, stack.unwind(ctx, err)
		}
		stack.Kv = started
	}
	if options.Storage {
		started, err := presetth.StartStorage(ctx, PresetStorageOptions{
			Key: key, Image: "", Bucket: "", Region: "",
			AccessKeyID: "", SecretAccessKey: "", Runtime: options.Runtime,
		})
		if err != nil {
			return nil, stack.unwind(ctx, err)
		}
		// No bucket creation here: StartStorage already creates the bucket its
		// block addresses, and creating it twice would surface as a conflict.
		stack.Storage = started
	}
	return stack, nil
}

// ErrEmptyStack reports a stack that was asked to boot nothing.
var ErrEmptyStack = errors.New("testhelper: a container stack needs at least one preset")

// Blocks renders the started presets as the configuration document fragment
// that addresses them.
//
// This is the glue the whole helper exists for: a Testcontainers port is only
// known at run time, so the block a service loads has to be BUILT from the
// started containers rather than written down in a fixture.
func (s *Stack) Blocks() map[string]any {
	blocks := map[string]any{}
	if s.Postgres != nil {
		blocks[standardconfig.PostgresBlockKey] = s.Postgres.Block
	}
	if s.Cache != nil {
		blocks[standardconfig.CacheBlockKey] = s.Cache.Block
	}
	if s.Kv != nil {
		blocks[standardconfig.KvBlockKey] = s.Kv.Block
	}
	if s.Storage != nil {
		blocks[standardconfig.StorageBlockKey] = s.Storage.Block
	}
	return blocks
}

// Terminate stops every started container, reporting the first failure but
// always attempting all of them.
func (s *Stack) Terminate(ctx context.Context) error {
	return s.unwind(ctx, nil)
}

// unwind terminates everything started so far and returns cause, or the first
// termination failure when cause is nil.
func (s *Stack) unwind(ctx context.Context, cause error) error {
	failure := cause
	if s.Storage != nil {
		failure = keepFirst(failure, s.Storage.Terminate(ctx))
		s.Storage = nil
	}
	if s.Kv != nil {
		failure = keepFirst(failure, s.Kv.Terminate(ctx))
		s.Kv = nil
	}
	if s.Cache != nil {
		failure = keepFirst(failure, s.Cache.Terminate(ctx))
		s.Cache = nil
	}
	if s.Postgres != nil {
		failure = keepFirst(failure, s.Postgres.Terminate(ctx))
		s.Postgres = nil
	}
	return failure
}

// keepFirst keeps the first failure seen, so a teardown error never masks the
// boot error that caused the teardown.
func keepFirst(first error, next error) error {
	if first != nil {
		return first
	}
	return next
}

// RequireStack fails the test unless a stack booted, and registers nothing:
// terminating it stays the caller's decision, because a suite usually shares one
// stack across many tests.
func RequireStack(t TestingT, stack *Stack, err error) *Stack {
	t.Helper()
	if err != nil {
		t.Fatalf("container stack did not start: %v", err)
	}
	return stack
}
