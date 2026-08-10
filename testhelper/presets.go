package testhelper

import (
	"context"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

// DefaultKey is the connection name every start helper uses when none is given.
// It is the name a first Postgres pool, cache, kv, or bucket conventionally
// carries.
const DefaultKey = "MAIN"

// Default images for the preset containers. Each is overridable per call so a
// consumer can pin the exact engine version its production landscape runs.
const (
	// DefaultPostgresImage backs [StartPostgres].
	DefaultPostgresImage = "postgres:16.4-alpine"
	// DefaultRedisImage backs [StartCache] and [StartKv]. Cache and kv differ by
	// durability configuration in a real landscape, not by protocol, so one
	// image serves both here.
	DefaultRedisImage = "redis:7.4.5-alpine"
	// DefaultStorageImage backs [StartStorage].
	DefaultStorageImage = "minio/minio:latest"
)

// In-container port specs for the preset containers.
const (
	postgresPort = "5432/tcp"
	redisPort    = "6379/tcp"
	storagePort  = "9000/tcp"
)

// PostgresOptions configures [StartPostgres]. The zero value is valid and
// starts a MAIN Postgres on the default image.
type PostgresOptions struct {
	// Key is the UPPERCASE connection name the emitted block is keyed by.
	// Blank means [DefaultKey].
	Key string
	// Image overrides [DefaultPostgresImage].
	Image string
	// Database is the database created on boot. Blank means "app".
	Database string
	// Username is the role created on boot. Blank means "app".
	Username string
	// Password is the role password. Blank means "app-secret". It is a REAL
	// value here, not the blank-in-YAML placeholder: the container has to
	// accept it.
	Password string
	// Runtime overrides the container runtime. Nil means [DockerRuntime].
	Runtime Runtime
}

// StartedPostgres is a running Postgres container and the postgres config block
// that addresses it.
type StartedPostgres struct {
	// Container is the running container.
	Container Container
	// Key is the UPPERCASE connection name the block is keyed by.
	Key string
	// Entry is the single resolved connection.
	Entry standardconfig.PostgresEntry
	// Block is the keyed block, valid against
	// [standardconfig.PostgresSchema].
	Block standardconfig.PostgresBlock
}

// Terminate stops and removes the container.
func (s *StartedPostgres) Terminate(ctx context.Context) error {
	return s.Container.Terminate(ctx)
}

// StartPostgres boots a Postgres container and emits the matching postgres
// block.
//
// The returned block is exactly what the preset schema accepts, keyed by an
// UPPERCASE name, so a consumer composes it into a test configuration document
// without translating anything by hand.
func StartPostgres(ctx context.Context, options PostgresOptions) (*StartedPostgres, error) {
	key := valueOr(options.Key, DefaultKey)
	database := valueOr(options.Database, "app")
	username := valueOr(options.Username, "app")
	password := valueOr(options.Password, "app-secret")
	running, err := endpoint(ctx, options.Runtime, testcontainers.ContainerRequest{
		Image:        valueOr(options.Image, DefaultPostgresImage),
		ExposedPorts: []string{postgresPort},
		Env: map[string]string{
			"POSTGRES_DB":       database,
			"POSTGRES_USER":     username,
			"POSTGRES_PASSWORD": password,
		},
		WaitingFor: wait.ForLog("database system is ready to accept connections").WithOccurrence(2),
	}, postgresPort)
	if err != nil {
		return nil, err
	}
	entry := standardconfig.PostgresEntry{
		Host:     running.host,
		Port:     running.port,
		Database: database,
		Username: username,
		Password: password,
		SSL:      false,
		Pool:     standardconfig.PoolSizing{Min: 0, Max: 10},
	}
	return &StartedPostgres{
		Container: running.container,
		Key:       key,
		Entry:     entry,
		Block:     standardconfig.PostgresBlock{key: entry},
	}, nil
}

// RedisOptions configures [StartCache] and [StartKv]. The zero value is valid.
type RedisOptions struct {
	// Key is the UPPERCASE connection name the emitted block is keyed by.
	// Blank means [DefaultKey].
	Key string
	// Image overrides [DefaultRedisImage].
	Image string
	// DB is the logical database index the emitted entry selects.
	DB int
	// Runtime overrides the container runtime. Nil means [DockerRuntime].
	Runtime Runtime
}

// StartedCache is a running cache container and the cache config block that
// addresses it.
type StartedCache struct {
	// Container is the running container.
	Container Container
	// Key is the UPPERCASE connection name the block is keyed by.
	Key string
	// Entry is the single resolved connection.
	Entry standardconfig.CacheEntry
	// Block is the keyed block, valid against [standardconfig.CacheSchema].
	Block standardconfig.CacheBlock
}

// Terminate stops and removes the container.
func (s *StartedCache) Terminate(ctx context.Context) error {
	return s.Container.Terminate(ctx)
}

// StartedKv is a running kv container and the kv config block that addresses
// it.
type StartedKv struct {
	// Container is the running container.
	Container Container
	// Key is the UPPERCASE connection name the block is keyed by.
	Key string
	// Entry is the single resolved connection.
	Entry standardconfig.KvEntry
	// Block is the keyed block, valid against [standardconfig.KvSchema].
	Block standardconfig.KvBlock
}

// Terminate stops and removes the container.
func (s *StartedKv) Terminate(ctx context.Context) error {
	return s.Container.Terminate(ctx)
}

// StartCache boots an ephemeral cache container and emits the matching cache
// block.
func StartCache(ctx context.Context, options RedisOptions) (*StartedCache, error) {
	started, err := startRedis(ctx, options)
	if err != nil {
		return nil, err
	}
	return &StartedCache{
		Container: started.container,
		Key:       started.key,
		Entry:     started.entry,
		Block:     standardconfig.CacheBlock{started.key: started.entry},
	}, nil
}

// StartKv boots a persistent kv container and emits the matching kv block.
//
// It is a SEPARATE container from [StartCache] by design. Pointing both presets
// at one instance would let a test pass while the deployment it stands for
// loses durable state on a cache eviction.
func StartKv(ctx context.Context, options RedisOptions) (*StartedKv, error) {
	started, err := startRedis(ctx, options)
	if err != nil {
		return nil, err
	}
	return &StartedKv{
		Container: started.container,
		Key:       started.key,
		Entry:     started.entry,
		Block:     standardconfig.KvBlock{started.key: started.entry},
	}, nil
}

// startedRedis is the shared outcome of booting a Redis-protocol container.
type startedRedis struct {
	container Container
	key       string
	entry     standardconfig.RedisEntry
}

// startRedis boots the Redis-protocol container both presets share and builds
// the common entry.
func startRedis(ctx context.Context, options RedisOptions) (startedRedis, error) {
	running, err := endpoint(ctx, options.Runtime, testcontainers.ContainerRequest{
		Image:        valueOr(options.Image, DefaultRedisImage),
		ExposedPorts: []string{redisPort},
		WaitingFor:   wait.ForLog("Ready to accept connections"),
	}, redisPort)
	if err != nil {
		return startedRedis{}, err
	}
	return startedRedis{
		container: running.container,
		key:       valueOr(options.Key, DefaultKey),
		entry: standardconfig.RedisEntry{
			Host:     running.host,
			Port:     running.port,
			Password: "",
			DB:       options.DB,
			TLS:      false,
		},
	}, nil
}

// StorageOptions configures [StartStorage]. The zero value is valid.
type StorageOptions struct {
	// Key is the UPPERCASE connection name the emitted block is keyed by.
	// Blank means [DefaultKey].
	Key string
	// Image overrides [DefaultStorageImage].
	Image string
	// Bucket is the bucket created after boot. Blank means "app".
	Bucket string
	// Region is the region label. Blank means "us-east-1".
	Region string
	// AccessKeyID is the root user. Blank means "minioadmin".
	AccessKeyID string
	// SecretAccessKey is the root password. Blank means "minioadmin".
	SecretAccessKey string
	// Runtime overrides the container runtime. Nil means [DockerRuntime].
	Runtime Runtime
}

// StartedStorage is a running S3-compatible container and the storage config
// block that addresses it.
type StartedStorage struct {
	// Container is the running container.
	Container Container
	// Key is the UPPERCASE connection name the block is keyed by.
	Key string
	// Entry is the single resolved connection.
	Entry standardconfig.StorageEntry
	// Block is the keyed block, valid against
	// [standardconfig.StorageSchema].
	Block standardconfig.StorageBlock
}

// Terminate stops and removes the container.
func (s *StartedStorage) Terminate(ctx context.Context) error {
	return s.Container.Terminate(ctx)
}

// StartStorage boots an S3-compatible container, creates the bucket, and emits
// the matching storage block.
//
// MinIO does not create a bucket on boot, so the helper creates it with
// [CreateBucket] before returning: a start helper that handed back a block
// pointing at a bucket that does not exist would move the failure into the
// consumer's first upload.
func StartStorage(ctx context.Context, options StorageOptions) (*StartedStorage, error) {
	key := valueOr(options.Key, DefaultKey)
	bucket := valueOr(options.Bucket, "app")
	region := valueOr(options.Region, "us-east-1")
	accessKeyID := valueOr(options.AccessKeyID, "minioadmin")
	secretAccessKey := valueOr(options.SecretAccessKey, "minioadmin")
	running, err := endpoint(ctx, options.Runtime, testcontainers.ContainerRequest{
		Image:        valueOr(options.Image, DefaultStorageImage),
		ExposedPorts: []string{storagePort},
		Env: map[string]string{
			"MINIO_ROOT_USER":     accessKeyID,
			"MINIO_ROOT_PASSWORD": secretAccessKey,
		},
		Cmd:        []string{"server", "/data"},
		WaitingFor: wait.ForLog("API:"),
	}, storagePort)
	if err != nil {
		return nil, err
	}
	entry := standardconfig.StorageEntry{
		Endpoint:        endpointURL(running.host, running.port),
		Region:          region,
		Bucket:          bucket,
		AccessKeyID:     accessKeyID,
		SecretAccessKey: secretAccessKey,
		ForcePathStyle:  true,
	}
	if err := CreateBucket(ctx, entry); err != nil {
		return nil, discard(ctx, running.container, err)
	}
	return &StartedStorage{
		Container: running.container,
		Key:       key,
		Entry:     entry,
		Block:     standardconfig.StorageBlock{key: entry},
	}, nil
}
