package appconfig

import (
	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

const (
	EncryptionBlockKey  = "encryption"
	TransportBlockKey   = "transport"
	ErrorPortalBlockKey = "errorPortal"
	DomainBlockKey      = "domain"
	DBInitBlockKey      = "dbInit"
	HealthBlockKey      = "health"
)

// EncryptionConfig configures AES-256-GCM payload protection.
type EncryptionConfig struct {
	Key string `json:"key" yaml:"key" jsonschema:"required"`
}

// TransportConfig configures the Redis streams consumer.
type TransportConfig struct {
	Stream        string `json:"stream" yaml:"stream" jsonschema:"required,minLength=1"`
	ConsumerGroup string `json:"consumerGroup" yaml:"consumerGroup" jsonschema:"required,minLength=1"`
	ConsumerName  string `json:"consumerName" yaml:"consumerName" jsonschema:"required,minLength=1"`
	BlockMS       int64  `json:"blockMs" yaml:"blockMs" jsonschema:"required,minimum=1,maximum=60000"`
	IdleMS        int64  `json:"idleMs" yaml:"idleMs" jsonschema:"required,minimum=0"`
	BatchSize     int64  `json:"batchSize" yaml:"batchSize" jsonschema:"required,minimum=1,maximum=100"`
}

// ErrorPortalConfig configures the single RFC 9457 type-URI builder.
type ErrorPortalConfig struct {
	Scheme    string `json:"scheme" yaml:"scheme" jsonschema:"required,enum=http,enum=https"`
	Host      string `json:"host" yaml:"host" jsonschema:"required,minLength=1"`
	Landscape string `json:"landscape" yaml:"landscape" jsonschema:"required,minLength=1"`
	Platform  string `json:"platform" yaml:"platform" jsonschema:"required,minLength=1"`
	Service   string `json:"service" yaml:"service" jsonschema:"required,minLength=1"`
	Module    string `json:"module" yaml:"module" jsonschema:"required,minLength=1"`
	Version   string `json:"version" yaml:"version" jsonschema:"required,pattern=^v[0-9]+$"`
}

// Portal returns the errors-problems portal without duplicating its URI template.
func (c ErrorPortalConfig) Portal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme: c.Scheme, Host: c.Host, Landscape: c.Landscape,
		Platform: c.Platform, Service: c.Service, Module: c.Module,
	}
}

// DomainConfig configures the fenced sample domain.
type DomainConfig struct {
	BlobPrefix      string `json:"blobPrefix" yaml:"blobPrefix" jsonschema:"required,minLength=1"`
	MaxMessageBytes int    `json:"maxMessageBytes" yaml:"maxMessageBytes" jsonschema:"required,minimum=1"`
}

// DBInitConfig configures the one-shot initializer.
type DBInitConfig struct {
	CreateBucket      bool   `json:"createBucket" yaml:"createBucket" jsonschema:"required"`
	MigrationsDir     string `json:"migrationsDir" yaml:"migrationsDir" jsonschema:"required,minLength=1"`
	RedisMigrationKey string `json:"redisMigrationKey" yaml:"redisMigrationKey" jsonschema:"required,minLength=1"`
	SeedDir           string `json:"seedDir" yaml:"seedDir" jsonschema:"required,minLength=1"`
}

// HealthConfig configures the dependency-blind worker heartbeat.
type HealthConfig struct {
	HeartbeatFile string `json:"heartbeatFile" yaml:"heartbeatFile" jsonschema:"required,minLength=1"`
	MaxAgeMS      int64  `json:"maxAgeMs" yaml:"maxAgeMs" jsonschema:"required,minimum=1"`
}

// ApplicationConfig is the fully decoded and validated configuration tree.
type ApplicationConfig struct {
	App         config.AppBlock              `json:"app" yaml:"app"`
	Otel        otel.Config                  `json:"otel" yaml:"otel"`
	Auth        authengine.Config            `json:"auth" yaml:"auth"`
	API         apiengine.Config             `json:"api" yaml:"api"`
	Postgres    standardconfig.PostgresBlock `json:"postgres" yaml:"postgres"`
	Cache       standardconfig.CacheBlock    `json:"cache" yaml:"cache"`
	Kv          standardconfig.KvBlock       `json:"kv" yaml:"kv"`
	Storage     standardconfig.StorageBlock  `json:"storage" yaml:"storage"`
	Encryption  EncryptionConfig             `json:"encryption" yaml:"encryption"`
	Transport   TransportConfig              `json:"transport" yaml:"transport"`
	ErrorPortal ErrorPortalConfig            `json:"errorPortal" yaml:"errorPortal"`
	Domain      DomainConfig                 `json:"domain" yaml:"domain"`
	DBInit      DBInitConfig                 `json:"dbInit" yaml:"dbInit"`
	Health      HealthConfig                 `json:"health" yaml:"health"`
}

// Fragmenter reflects an application-owned Go model into a JSON Schema fragment.
type Fragmenter func(model any) (map[string]any, error)

// OwnBlocks reflects every service-owned configuration block from its Go type.
func OwnBlocks() ([]config.Block, error) {
	return OwnBlocksWith(config.FragmentFromType)
}

// OwnBlocksWith reflects service-owned blocks using an injectable reflector.
func OwnBlocksWith(fragment Fragmenter) ([]config.Block, error) {
	models := []struct {
		key   string
		model any
	}{
		{EncryptionBlockKey, EncryptionConfig{}},
		{TransportBlockKey, TransportConfig{}},
		{ErrorPortalBlockKey, ErrorPortalConfig{}},
		{DomainBlockKey, DomainConfig{}},
		{DBInitBlockKey, DBInitConfig{}},
		{HealthBlockKey, HealthConfig{}},
	}
	blocks := make([]config.Block, 0, len(models))
	for _, model := range models {
		reflected, err := fragment(model.model)
		if err != nil {
			return nil, err
		}
		blocks = append(blocks, config.NewBlock(model.key, true, reflected))
	}
	return blocks, nil
}

// Schema composes the application root schema in the contract-defined order.
func Schema() (config.Schema, error) {
	return SchemaWith(config.FragmentFromType)
}

// SchemaWith composes the root schema using an injectable service-block reflector.
func SchemaWith(fragment Fragmenter) (config.Schema, error) {
	own, err := OwnBlocksWith(fragment)
	if err != nil {
		return config.Schema{}, err
	}
	blocks := []config.Block{
		config.AppBlockSchema(),
		config.NewBlock(otel.SchemaKey(), true, otel.JSONSchema()),
		config.NewBlock(authengine.ConfigBlockKey, true, authengine.ConfigBlockSchema()),
		config.NewBlock(apiengine.ConfigBlockKey, true, apiengine.ConfigBlockSchema()),
		config.NewBlock(standardconfig.PostgresBlockKey, true, standardconfig.PostgresSchema()),
		config.NewBlock(standardconfig.CacheBlockKey, true, standardconfig.CacheSchema()),
		config.NewBlock(standardconfig.KvBlockKey, true, standardconfig.KvSchema()),
		config.NewBlock(standardconfig.StorageBlockKey, true, standardconfig.StorageSchema()),
	}
	blocks = append(blocks, own...)
	return config.ComposeSchema(blocks...), nil
}

// Decode converts the validated tree into application-owned typed blocks.
func Decode(cfg *config.Config) (ApplicationConfig, error) {
	app, err := cfg.App()
	if err != nil {
		return ApplicationConfig{}, err
	}
	decoded := ApplicationConfig{App: app}
	blocks := []struct {
		key    string
		target any
	}{
		{otel.SchemaKey(), &decoded.Otel},
		{authengine.ConfigBlockKey, &decoded.Auth},
		{apiengine.ConfigBlockKey, &decoded.API},
		{standardconfig.PostgresBlockKey, &decoded.Postgres},
		{standardconfig.CacheBlockKey, &decoded.Cache},
		{standardconfig.KvBlockKey, &decoded.Kv},
		{standardconfig.StorageBlockKey, &decoded.Storage},
		{EncryptionBlockKey, &decoded.Encryption},
		{TransportBlockKey, &decoded.Transport},
		{ErrorPortalBlockKey, &decoded.ErrorPortal},
		{DomainBlockKey, &decoded.Domain},
		{DBInitBlockKey, &decoded.DBInit},
		{HealthBlockKey, &decoded.Health},
	}
	for _, block := range blocks {
		if err := cfg.Decode(block.key, block.target); err != nil {
			return ApplicationConfig{}, err
		}
	}
	return decoded, nil
}
