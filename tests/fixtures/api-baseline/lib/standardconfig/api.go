package standardconfig

import (
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

const (
	ProblemVersion              = "v1"
	ProblemConnectionUnknown    = "connection-unknown"
	ProblemConnectionAmbiguous  = "connection-ambiguous"
	ProblemConnectionKeyInvalid = "connection-key-invalid"
	ProblemPresetUnknown        = "preset-unknown"

	UppercaseKeyPattern   = `^[A-Z][A-Z0-9_]*$`
	ConnectionNamePattern = `^[A-Za-z][A-Za-z0-9_]*$`

	PostgresBlockKey = "postgres"
	CacheBlockKey    = "cache"
	KvBlockKey       = "kv"
	StorageBlockKey  = "storage"
)

type Problems struct{ uncomparable []struct{} }

func ProblemTypes() []problem.Type { return nil }

func NewProblems(problem.ErrorPortal, ...problem.Type) (*Problems, error) { return nil, nil }

func (*Problems) Registry() *problem.Registry { return nil }

func (*Problems) Catalog() (*problem.Catalog, error) { return nil, nil }

func (*Problems) Raise(string, string, map[string]any) error { return nil }

func ValidKey(string) bool { return false }

func ValidConnectionName(string) bool { return false }

func Keys[E any](map[string]E) []string { return nil }

func Named[E any](*Problems, map[string]E, string) (E, error) {
	var zero E
	return zero, nil
}

func ValidateKeys[E any](*Problems, string, map[string]E) error { return nil }

type PoolSizing struct {
	Min int `json:"min" yaml:"min"`
	Max int `json:"max" yaml:"max"`
}

type PostgresEntry struct {
	Host     string     `json:"host" yaml:"host"`
	Port     int        `json:"port" yaml:"port"`
	Database string     `json:"database" yaml:"database"`
	Username string     `json:"username" yaml:"username"`
	Password string     `json:"password" yaml:"password"`
	SSL      bool       `json:"ssl" yaml:"ssl"`
	Pool     PoolSizing `json:"pool" yaml:"pool"`
}

type PostgresBlock = map[string]PostgresEntry

func PostgresSchema() map[string]any { return nil }

type RedisEntry struct {
	Host     string `json:"host" yaml:"host"`
	Port     int    `json:"port" yaml:"port"`
	Password string `json:"password" yaml:"password"`
	DB       int    `json:"db" yaml:"db"`
	TLS      bool   `json:"tls" yaml:"tls"`
}

type (
	CacheEntry = RedisEntry
	CacheBlock = map[string]CacheEntry
	KvEntry    = RedisEntry
	KvBlock    = map[string]KvEntry
)

func CacheSchema() map[string]any { return nil }

func KvSchema() map[string]any { return nil }

type StorageEntry struct {
	Endpoint        string `json:"endpoint" yaml:"endpoint"`
	Region          string `json:"region" yaml:"region"`
	Bucket          string `json:"bucket" yaml:"bucket"`
	AccessKeyID     string `json:"accessKeyId" yaml:"accessKeyId"`
	SecretAccessKey string `json:"secretAccessKey" yaml:"secretAccessKey"`
	ForcePathStyle  bool   `json:"forcePathStyle" yaml:"forcePathStyle"`
}

type StorageBlock = map[string]StorageEntry

func StorageSchema() map[string]any { return nil }

func PresetNames() []string { return nil }

func Schemas() map[string]map[string]any { return nil }

func SchemaFor(*Problems, string) (map[string]any, error) { return nil, nil }
