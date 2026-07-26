package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"slices"
	"strings"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-consumer/adapters/postgres"
	redisadapter "github.com/AtomiCloud/diene.go-consumer/adapters/redis"
	"github.com/AtomiCloud/diene.go-consumer/adapters/storage"
	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	"github.com/AtomiCloud/diene.go-consumer/lib/appconfig"
	"github.com/AtomiCloud/diene.go-consumer/lib/publishedapi"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

type runtimeResources struct {
	config         appconfig.ApplicationConfig
	telemetry      *otelsdk.Runtime
	tracer         *tracing.Tracer
	postgres       map[string]*postgres.Pool
	cache          map[string]*redisadapter.Client
	kv             map[string]*redisadapter.Client
	storage        map[string]*storage.Client
	postgresMain   *postgres.Pool
	cacheMain      *redisadapter.Client
	kvMain         *redisadapter.Client
	storageMain    *storage.Client
	storageArchive *storage.Client
	published      *apiengine.ClientTree
}

func (a *Application) createRuntime(
	ctx context.Context,
	config appconfig.ApplicationConfig,
	system *invocationSystem,
	logWriter io.Writer,
) (*runtimeResources, error) {
	standardProblems, err := standardconfig.NewProblems(config.ErrorPortal.Portal())
	if err != nil {
		return nil, fmt.Errorf("runtime: construct standard-config problems: %w", err)
	}
	blocks := []struct {
		key      string
		validate func() error
	}{
		{standardconfig.PostgresBlockKey, func() error {
			return standardconfig.ValidateKeys(standardProblems, standardconfig.PostgresBlockKey, config.Postgres)
		}},
		{standardconfig.CacheBlockKey, func() error {
			return standardconfig.ValidateKeys(standardProblems, standardconfig.CacheBlockKey, config.Cache)
		}},
		{standardconfig.KvBlockKey, func() error {
			return standardconfig.ValidateKeys(standardProblems, standardconfig.KvBlockKey, config.Kv)
		}},
		{standardconfig.StorageBlockKey, func() error {
			return standardconfig.ValidateKeys(standardProblems, standardconfig.StorageBlockKey, config.Storage)
		}},
	}
	for _, block := range blocks {
		if validateErr := block.validate(); validateErr != nil {
			return nil, fmt.Errorf("runtime: validate %s connection keys: %w", block.key, validateErr)
		}
	}
	identity := otel.AppIdentity{
		Landscape: config.App.Landscape,
		Platform:  config.App.Platform,
		Service:   config.App.Service,
		Module:    config.App.Module,
		Version:   config.App.Version,
	}
	a.registrationMu.Lock()
	registerGlobally := !a.globalRegistered
	telemetry, err := otelsdk.New(
		ctx,
		config.Otel,
		identity,
		otelsdk.WithSystem(system),
		otelsdk.WithLogWriter(logWriter),
		otelsdk.WithGlobalRegistration(registerGlobally),
	)
	if err == nil && registerGlobally {
		a.globalRegistered = true
	}
	a.registrationMu.Unlock()
	if err != nil {
		return nil, fmt.Errorf("runtime: construct telemetry: %w", err)
	}
	resources := &runtimeResources{
		config:    config,
		telemetry: telemetry,
		postgres:  make(map[string]*postgres.Pool, len(config.Postgres)),
		cache:     make(map[string]*redisadapter.Client, len(config.Cache)),
		kv:        make(map[string]*redisadapter.Client, len(config.Kv)),
		storage:   make(map[string]*storage.Client, len(config.Storage)),
	}
	fail := func(cause error) (*runtimeResources, error) {
		return nil, errors.Join(cause, resources.Close(ctx))
	}
	resources.tracer, err = tracing.New(system, telemetry.TraceEmitter())
	if err != nil {
		return fail(fmt.Errorf("runtime: construct adapter tracer: %w", err))
	}
	for _, name := range standardconfig.Keys(config.Postgres) {
		client, openErr := postgres.Open(ctx, config.Postgres[name], resources.tracer)
		if openErr != nil {
			return fail(fmt.Errorf("runtime: open postgres %q: %w", name, openErr))
		}
		resources.postgres[name] = client
	}
	for _, name := range standardconfig.Keys(config.Cache) {
		client, openErr := redisadapter.Open(config.Cache[name], resources.tracer)
		if openErr != nil {
			return fail(fmt.Errorf("runtime: open cache %q: %w", name, openErr))
		}
		resources.cache[name] = client
	}
	for _, name := range standardconfig.Keys(config.Kv) {
		client, openErr := redisadapter.Open(config.Kv[name], resources.tracer)
		if openErr != nil {
			return fail(fmt.Errorf("runtime: open kv %q: %w", name, openErr))
		}
		resources.kv[name] = client
	}
	for _, name := range standardconfig.Keys(config.Storage) {
		client, openErr := storage.Open(ctx, config.Storage[name], resources.tracer)
		if openErr != nil {
			return fail(fmt.Errorf("runtime: open storage %q: %w", name, openErr))
		}
		resources.storage[name] = client
	}
	resources.postgresMain, err = namedClient(standardProblems, config.Postgres, resources.postgres, appconfig.PostgresMain)
	if err != nil {
		return fail(fmt.Errorf("runtime: resolve primary postgres: %w", err))
	}
	resources.cacheMain, err = namedClient(standardProblems, config.Cache, resources.cache, appconfig.CacheMain)
	if err != nil {
		return fail(fmt.Errorf("runtime: resolve primary cache: %w", err))
	}
	resources.kvMain, err = namedClient(standardProblems, config.Kv, resources.kv, appconfig.KvMain)
	if err != nil {
		return fail(fmt.Errorf("runtime: resolve primary kv: %w", err))
	}
	resources.storageMain, err = namedClient(standardProblems, config.Storage, resources.storage, appconfig.StorageMain)
	if err != nil {
		return fail(fmt.Errorf("runtime: resolve primary storage: %w", err))
	}
	resources.storageArchive, err = namedClient(standardProblems, config.Storage, resources.storage, appconfig.StorageArchive)
	if err != nil {
		return fail(fmt.Errorf("runtime: resolve archive storage: %w", err))
	}
	tokenStore, err := redisadapter.NewTokenStore(resources.cacheMain)
	if err != nil {
		return fail(fmt.Errorf("runtime: construct auth token store: %w", err))
	}
	resources.published, err = publishedapi.NewClientTree(
		config.ErrorPortal.Portal(),
		config.API,
		config.Auth,
		tokenStore,
		system,
		nil,
	)
	if err != nil {
		return fail(fmt.Errorf("runtime: construct published clients: %w", err))
	}
	return resources, nil
}

func namedClient[Entry any, Client any](
	problems *standardconfig.Problems,
	block map[string]Entry,
	clients map[string]Client,
	name string,
) (Client, error) {
	var zero Client
	if _, err := standardconfig.Named(problems, block, name); err != nil {
		return zero, err
	}
	for declared, client := range clients {
		if strings.EqualFold(declared, name) {
			return client, nil
		}
	}
	return zero, fmt.Errorf("configured adapter %q was not constructed", name)
}

// Close releases every started resource. All failures are retained; callers
// join this result with any original command or construction error.
func (runtime *runtimeResources) Close(ctx context.Context) error {
	if runtime == nil {
		return nil
	}
	failures := make([]error, 0)
	postgresNames := sortedMapKeys(runtime.postgres)
	for _, name := range slices.Backward(postgresNames) {
		if err := runtime.postgres[name].Close(); err != nil {
			failures = append(failures, fmt.Errorf("close postgres %q: %w", name, err))
		}
	}
	cacheNames := sortedMapKeys(runtime.cache)
	for _, name := range slices.Backward(cacheNames) {
		if err := runtime.cache[name].Close(); err != nil {
			failures = append(failures, fmt.Errorf("close cache %q: %w", name, err))
		}
	}
	kvNames := sortedMapKeys(runtime.kv)
	for _, name := range slices.Backward(kvNames) {
		if err := runtime.kv[name].Close(); err != nil {
			failures = append(failures, fmt.Errorf("close kv %q: %w", name, err))
		}
	}
	if runtime.telemetry != nil {
		if err := runtime.telemetry.Shutdown(ctx); err != nil {
			failures = append(failures, fmt.Errorf("shutdown telemetry: %w", err))
		}
	}
	return errors.Join(failures...)
}

func sortedMapKeys[Value any](values map[string]Value) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	return keys
}
