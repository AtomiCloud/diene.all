package testhelper

import (
	"context"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/testcontainers/testcontainers-go"
)

const (
	DefaultKey           = "MAIN"
	DefaultPostgresImage = "postgres:16.4-alpine"
	DefaultRedisImage    = "redis:7.4.5-alpine"
	DefaultStorageImage  = "minio/minio:latest"
)

type Container interface {
	Host(ctx context.Context) (string, error)
	Port(ctx context.Context, spec string) (int, error)
	Terminate(ctx context.Context) error
}

type Runtime interface {
	Start(ctx context.Context, request testcontainers.ContainerRequest) (Container, error)
}

type DockerRuntime struct{}

func (DockerRuntime) Start(context.Context, testcontainers.ContainerRequest) (Container, error) {
	return nil, nil
}

type PostgresOptions struct {
	Key      string
	Image    string
	Database string
	Username string
	Password string
	Runtime  Runtime
}

type StartedPostgres struct {
	Container Container
	Key       string
	Entry     standardconfig.PostgresEntry
	Block     standardconfig.PostgresBlock
}

func (*StartedPostgres) Terminate(context.Context) error { return nil }

func StartPostgres(context.Context, PostgresOptions) (*StartedPostgres, error) { return nil, nil }

type RedisOptions struct {
	Key     string
	Image   string
	DB      int
	Runtime Runtime
}

type StartedCache struct {
	Container Container
	Key       string
	Entry     standardconfig.CacheEntry
	Block     standardconfig.CacheBlock
}

func (*StartedCache) Terminate(context.Context) error { return nil }

type StartedKv struct {
	Container Container
	Key       string
	Entry     standardconfig.KvEntry
	Block     standardconfig.KvBlock
}

func (*StartedKv) Terminate(context.Context) error { return nil }

func StartCache(context.Context, RedisOptions) (*StartedCache, error) { return nil, nil }

func StartKv(context.Context, RedisOptions) (*StartedKv, error) { return nil, nil }

type StorageOptions struct {
	Key             string
	Image           string
	Bucket          string
	Region          string
	AccessKeyID     string
	SecretAccessKey string
	Runtime         Runtime
}

type StartedStorage struct {
	Container Container
	Key       string
	Entry     standardconfig.StorageEntry
	Block     standardconfig.StorageBlock
}

func (*StartedStorage) Terminate(context.Context) error { return nil }

func StartStorage(context.Context, StorageOptions) (*StartedStorage, error) { return nil, nil }

func CreateBucket(context.Context, standardconfig.StorageEntry) error { return nil }

func FakePostgres(string) standardconfig.PostgresBlock { return nil }

func FakeCache(string) standardconfig.CacheBlock { return nil }

func FakeKv(string) standardconfig.KvBlock { return nil }

func FakeStorage(string) standardconfig.StorageBlock { return nil }

type TestingT interface {
	Helper()
	Fatalf(format string, args ...any)
}

func RequireStarted[S any](TestingT, *S, error) *S { return nil }

func RequireEntry[E any](TestingT, map[string]E, string) E {
	var zero E
	return zero
}

func RequireUppercaseKeys[E any](TestingT, map[string]E) {}

func RequireConnectionNames[E any](TestingT, map[string]E) {}
