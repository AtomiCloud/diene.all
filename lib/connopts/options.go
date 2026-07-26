package connopts

import (
	"crypto/tls"
	"net"
	"net/url"
	"strconv"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// PostgresOptions contains the values needed to construct a pgx pool.
type PostgresOptions struct {
	ConnectionString string
	MinConnections   int
	MaxConnections   int
}

// RedisOptions contains the values needed to construct redis.Options.
type RedisOptions struct {
	Address   string
	Password  string
	DB        int
	TLSConfig *tls.Config
}

// StorageOptions contains the values needed to construct an AWS S3 client.
type StorageOptions struct {
	Endpoint        string
	Region          string
	Bucket          string
	AccessKeyID     string
	SecretAccessKey string
	UsePathStyle    bool
}

// Postgres maps a frozen Postgres config entry into pool construction options.
func Postgres(entry standardconfig.PostgresEntry) PostgresOptions {
	sslMode := "disable"
	if entry.SSL {
		sslMode = "require"
	}
	connectionURL := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(entry.Username, entry.Password),
		Host:     net.JoinHostPort(entry.Host, strconv.Itoa(entry.Port)),
		Path:     entry.Database,
		RawQuery: url.Values{"sslmode": []string{sslMode}}.Encode(),
	}
	return PostgresOptions{
		ConnectionString: connectionURL.String(),
		MinConnections:   entry.Pool.Min,
		MaxConnections:   entry.Pool.Max,
	}
}

// Redis maps a frozen Redis-protocol config entry into client options.
func Redis(entry standardconfig.RedisEntry) RedisOptions {
	var tlsConfig *tls.Config
	if entry.TLS {
		tlsConfig = &tls.Config{MinVersion: tls.VersionTLS12, ServerName: entry.Host}
	}
	return RedisOptions{
		Address:   net.JoinHostPort(entry.Host, strconv.Itoa(entry.Port)),
		Password:  entry.Password,
		DB:        entry.DB,
		TLSConfig: tlsConfig,
	}
}

// Storage maps a frozen storage config entry into AWS client options.
func Storage(entry standardconfig.StorageEntry) StorageOptions {
	return StorageOptions{
		Endpoint:        entry.Endpoint,
		Region:          entry.Region,
		Bucket:          entry.Bucket,
		AccessKeyID:     entry.AccessKeyID,
		SecretAccessKey: entry.SecretAccessKey,
		UsePathStyle:    entry.ForcePathStyle,
	}
}
