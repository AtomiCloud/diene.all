package connopts_test

import (
	"crypto/tls"
	"net/url"
	"testing"

	"github.com/AtomiCloud/diene.go-consumer/lib/connopts"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

func TestPostgres(t *testing.T) {
	t.Parallel()
	for _, test := range []struct {
		name string
		ssl  bool
		want string
	}{
		{name: "disabled", ssl: false, want: "disable"},
		{name: "required", ssl: true, want: "require"},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			actual := connopts.Postgres(standardconfig.PostgresEntry{
				Host: "postgres", Port: 5432, Database: "consumer", Username: "worker",
				Password: "p@ss word", SSL: test.ssl, Pool: standardconfig.PoolSizing{Min: 1, Max: 8},
			})
			parsed, err := url.Parse(actual.ConnectionString)
			if err != nil {
				t.Fatalf("parse connection string: %v", err)
			}
			password, _ := parsed.User.Password()
			if parsed.Host != "postgres:5432" || parsed.Path != "/consumer" || parsed.User.Username() != "worker" || password != "p@ss word" {
				t.Fatalf("unexpected connection string %q", actual.ConnectionString)
			}
			if parsed.Query().Get("sslmode") != test.want {
				t.Fatalf("sslmode = %q, want %q", parsed.Query().Get("sslmode"), test.want)
			}
			if actual.MinConnections != 1 || actual.MaxConnections != 8 {
				t.Fatalf("pool sizing = %d..%d", actual.MinConnections, actual.MaxConnections)
			}
		})
	}
}

func TestRedis(t *testing.T) {
	t.Parallel()
	plain := connopts.Redis(standardconfig.RedisEntry{Host: "redis", Port: 6379, Password: "", DB: 1})
	if plain.Address != "redis:6379" || plain.Password != "" || plain.DB != 1 || plain.TLSConfig != nil {
		t.Fatalf("plain options = %#v", plain)
	}
	secure := connopts.Redis(standardconfig.RedisEntry{
		Host: "redis.internal", Port: 6380, Password: "secret", DB: 2, TLS: true,
	})
	if secure.Address != "redis.internal:6380" || secure.Password != "secret" || secure.DB != 2 {
		t.Fatalf("secure options = %#v", secure)
	}
	if secure.TLSConfig == nil || secure.TLSConfig.ServerName != "redis.internal" || secure.TLSConfig.MinVersion != tls.VersionTLS12 {
		t.Fatalf("secure TLS config = %#v", secure.TLSConfig)
	}
}

func TestStorage(t *testing.T) {
	t.Parallel()
	actual := connopts.Storage(standardconfig.StorageEntry{
		Endpoint: "http://minio:9000", Region: "us-east-1", Bucket: "consumer",
		AccessKeyID: "key", SecretAccessKey: "secret", ForcePathStyle: true,
	})
	if actual.Endpoint != "http://minio:9000" || actual.Region != "us-east-1" || actual.Bucket != "consumer" ||
		actual.AccessKeyID != "key" || actual.SecretAccessKey != "secret" || !actual.UsePathStyle {
		t.Fatalf("storage options = %#v", actual)
	}
	virtualHosted := connopts.Storage(standardconfig.StorageEntry{ForcePathStyle: false})
	if virtualHosted.UsePathStyle {
		t.Fatal("forcePathStyle=false unexpectedly enabled path style")
	}
}
