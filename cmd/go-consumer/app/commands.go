package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/adapters/redisstreams"
	"github.com/AtomiCloud/diene.go-consumer/lib/dbinit"
	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
	"github.com/AtomiCloud/diene.go-consumer/lib/encryption"
	"github.com/AtomiCloud/diene.go-consumer/lib/health"
	"github.com/AtomiCloud/diene.go-consumer/lib/messagecodec"
	"github.com/AtomiCloud/diene.go-consumer/lib/seedrecord"
	"github.com/AtomiCloud/diene.go-consumer/lib/worker"
	"github.com/AtomiCloud/diene.go-e2e/adapters/filesystem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/spf13/cobra"
)

func (a *Application) workerCommand(
	root string,
	invocation Invocation,
	stdout io.Writer,
	landscape *string,
) *cobra.Command {
	var once bool
	command := &cobra.Command{
		Use:   "worker",
		Short: "run the Redis streams consumer",
		Args:  cobra.NoArgs,
	}
	command.Flags().BoolVar(&once, "once", false, "process one polling cycle and stop")
	command.RunE = wrapRuntime(func(ctx context.Context) error {
		return a.runWorker(ctx, root, invocation, stdout, *landscape, once)
	})
	return command
}

func (a *Application) dbInitCommand(
	root string,
	invocation Invocation,
	stdout io.Writer,
	landscape *string,
) *cobra.Command {
	return &cobra.Command{
		Use:   "db-init",
		Short: "check dependencies, migrate, and seed idempotently",
		Args:  cobra.NoArgs,
		RunE: wrapRuntime(func(ctx context.Context) error {
			return a.runDBInit(ctx, root, invocation, stdout, *landscape)
		}),
	}
}

func (a *Application) healthCommand(
	root string,
	invocation Invocation,
	stdout io.Writer,
	landscape *string,
) *cobra.Command {
	return &cobra.Command{
		Use:   "health",
		Short: "check the dependency-blind worker heartbeat",
		Args:  cobra.NoArgs,
		RunE: wrapRuntime(func(ctx context.Context) error {
			return a.runHealth(ctx, root, invocation, stdout, *landscape)
		}),
	}
}

func (a *Application) runWorker(
	ctx context.Context,
	root string,
	invocation Invocation,
	stdout io.Writer,
	landscape string,
	once bool,
) (resultErr error) {
	configured, err := loadApplicationConfig(ctx, root, landscape, invocation.Env)
	if err != nil {
		return err
	}
	system := newInvocationSystem(invocation)
	runtime, err := a.createRuntime(ctx, configured, system, stdout)
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, runtime.Close(ctx)) }()
	heartbeatPath, err := rootedPath(root, configured.Health.HeartbeatFile)
	if err != nil {
		return err
	}
	heartbeat, err := health.NewFileHeartbeat(filesystem.NewVfs(), system, health.Options{
		Path: heartbeatPath, MaxAge: time.Duration(configured.Health.MaxAgeMS) * time.Millisecond, PID: a.pid,
	})
	if err != nil {
		return err
	}
	encryptor, err := encryption.NewAES256GCM(configured.Encryption.Key, nil)
	if err != nil {
		return err
	}
	if runtime.kvMain.Native() == nil {
		return errors.New("worker: primary kv adapter has no Redis streams client")
	}
	transport, err := redisstreams.New(runtime.kvMain.Native(), redisstreams.Config{
		Stream:    configured.Transport.Stream,
		Group:     configured.Transport.ConsumerGroup,
		Consumer:  configured.Transport.ConsumerName,
		Block:     time.Duration(configured.Transport.BlockMS) * time.Millisecond,
		Idle:      time.Duration(configured.Transport.IdleMS) * time.Millisecond,
		BatchSize: configured.Transport.BatchSize,
	}, runtime.tracer)
	if err != nil {
		return err
	}

	// ─── DOMAIN WIRING · go-consumer sample ───
	domainProblems, err := domain.NewProblems(
		configured.ErrorPortal.Portal(),
		configured.Transport.Stream,
		configured.ErrorPortal.Version,
	)
	if err != nil {
		return err
	}
	domainHandler, err := domain.NewSampleWorkerHandler(
		domainProblems,
		runtime.postgresMain,
		runtime.storageMain,
		encryptor,
		configured.Domain.BlobPrefix,
	)
	if err != nil {
		return err
	}
	consumer, err := worker.NewConsumer(worker.Options[messagecodec.WorkerMessage]{
		Transport:       transport,
		Decoder:         messageDecoder{},
		Handler:         workerHandler{handler: domainHandler},
		Heartbeat:       heartbeat,
		System:          system,
		Logger:          runtime.telemetry.LoggerSinkContext(ctx),
		Metrics:         runtime.telemetry.MetricsCollector(),
		MaxMessageBytes: configured.Domain.MaxMessageBytes,
		IdentityAttributes: map[string]string{
			"atomi.consumer.name":    configured.Transport.ConsumerName,
			"atomi.landscape":        configured.App.Landscape,
			"atomi.module":           configured.App.Module,
			"atomi.platform":         configured.App.Platform,
			"atomi.service":          configured.App.Service,
			"atomi.transport.stream": configured.Transport.Stream,
		},
	})
	// ─── END DOMAIN WIRING · go-consumer sample ───
	if err != nil {
		return err
	}
	return consumer.Run(ctx, once)
}

func (a *Application) runDBInit(
	ctx context.Context,
	root string,
	invocation Invocation,
	stdout io.Writer,
	landscape string,
) (resultErr error) {
	configured, err := loadApplicationConfig(ctx, root, landscape, invocation.Env)
	if err != nil {
		return err
	}
	system := newInvocationSystem(invocation)
	runtime, err := a.createRuntime(ctx, configured, system, stdout)
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, runtime.Close(ctx)) }()
	migrationsDirectory, err := rootedPath(root, configured.DBInit.MigrationsDir)
	if err != nil {
		return err
	}
	seedDirectory, err := rootedPath(root, configured.DBInit.SeedDir)
	if err != nil {
		return err
	}
	filesystemAdapter := filesystem.NewVfs()
	reachability, err := dbinit.NewReachabilityChecks(dbinit.ReachabilityOptions{
		Postgres: namedPostgresProbes(runtime.postgres),
		Redis:    namedRedisProbes(runtime.cache, runtime.kv),
		Storage:  namedStorageProbes(runtime.storage),
	})
	if err != nil {
		return err
	}
	buckets, err := dbinit.NewBucketCreator(
		configured.DBInit.CreateBucket,
		namedBuckets(runtime.storage),
	)
	if err != nil {
		return err
	}
	migrations, err := dbinit.NewMigrationRunner(dbinit.MigrationOptions{
		Filesystem: filesystemAdapter,
		Postgres:   runtime.postgresMain,
		Redis:      runtime.kvMain,
		Directory:  migrationsDirectory,
		MarkerKey:  configured.DBInit.RedisMigrationKey,
	})
	if err != nil {
		return err
	}

	// ─── DOMAIN WIRING · go-consumer seed sample ───
	seeds, err := dbinit.NewSeedLoader(dbinit.SeedOptions[seedrecord.Record]{
		Filesystem: filesystemAdapter,
		Parser:     seedParser{},
		Store:      runtime.postgresMain,
		ID:         func(record seedrecord.Record) string { return record.ID },
		Directory:  seedDirectory,
	})
	// ─── END DOMAIN WIRING · go-consumer seed sample ───
	if err != nil {
		return err
	}
	initializer, err := dbinit.NewInitializer(dbinit.InitializerOptions{
		Reachability: reachability,
		Buckets:      buckets,
		Migrations:   migrations,
		Seeds:        seeds,
	})
	if err != nil {
		return err
	}
	result, err := initializer.Run(ctx)
	if err != nil {
		return err
	}
	return json.NewEncoder(stdout).Encode(struct {
		OK     bool `json:"ok"`
		Seeded int  `json:"seeded"`
	}{OK: true, Seeded: result.Seeded})
}

func (a *Application) runHealth(
	ctx context.Context,
	root string,
	invocation Invocation,
	stdout io.Writer,
	landscape string,
) error {
	configured, err := loadApplicationConfig(ctx, root, landscape, invocation.Env)
	if err != nil {
		return err
	}
	heartbeatPath, err := rootedPath(root, configured.Health.HeartbeatFile)
	if err != nil {
		return err
	}
	heartbeat, err := health.NewFileHeartbeat(
		filesystem.NewVfs(),
		newInvocationSystem(invocation),
		health.Options{
			Path: heartbeatPath, MaxAge: time.Duration(configured.Health.MaxAgeMS) * time.Millisecond, PID: a.pid,
		},
	)
	if err != nil {
		return err
	}
	result := heartbeat.Check(ctx)
	if err := json.NewEncoder(stdout).Encode(result); err != nil {
		return fmt.Errorf("health: encode result: %w", err)
	}
	if !result.Healthy {
		return errors.New(result.Reason)
	}
	return nil
}

type messageDecoder struct{}

func (messageDecoder) Decode(_ context.Context, payload string) (messagecodec.WorkerMessage, error) {
	return messagecodec.Decode(payload)
}

type workerHandler struct{ handler *domain.SampleWorkerHandler }

func (handler workerHandler) Handle(
	ctx context.Context,
	message messagecodec.WorkerMessage,
) (worker.HandleResult, error) {
	result, err := handler.handler.Handle(ctx, message)
	return worker.HandleResult{
		MessageID: message.ID,
		Inserted:  result.Inserted,
		ObjectKey: result.ObjectKey,
	}, err
}

type seedParser struct{}

func (seedParser) Parse(data []byte) ([]seedrecord.Record, error) {
	return seedrecord.Parse(data)
}

func namedPostgresProbes[Client dbinit.Probe](values map[string]Client) []dbinit.NamedProbe {
	probes := make([]dbinit.NamedProbe, 0, len(values))
	for _, name := range sortedMapKeys(values) {
		probes = append(probes, dbinit.NamedProbe{Name: name, Probe: values[name]})
	}
	return probes
}

func namedRedisProbes[Client dbinit.Probe](groups ...map[string]Client) []dbinit.NamedProbe {
	probes := make([]dbinit.NamedProbe, 0)
	for _, values := range groups {
		for _, name := range sortedMapKeys(values) {
			probes = append(probes, dbinit.NamedProbe{Name: name, Probe: values[name]})
		}
	}
	return probes
}

func namedStorageProbes[Client dbinit.Probe](values map[string]Client) []dbinit.NamedProbe {
	probes := make([]dbinit.NamedProbe, 0, len(values))
	for _, name := range sortedMapKeys(values) {
		probes = append(probes, dbinit.NamedProbe{Name: name, Probe: values[name]})
	}
	return probes
}

func namedBuckets[Provisioner dbinit.BucketProvisioner](values map[string]Provisioner) []dbinit.NamedBucket {
	buckets := make([]dbinit.NamedBucket, 0, len(values))
	for _, name := range sortedMapKeys(values) {
		buckets = append(buckets, dbinit.NamedBucket{Name: name, Provisioner: values[name]})
	}
	return buckets
}

var _ interfaces.System = (*invocationSystem)(nil)
