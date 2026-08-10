package testhelper

import "github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"

// FakePostgres returns a container-free postgres block for unit tiers.
//
// The values are deterministic and the secret is blank, exactly as the
// committed YAML carries it (R14/M33), so a unit test asserting on a decoded
// block never depends on a port the kernel happened to hand out.
func FakePostgres(key string) standardconfig.PostgresBlock {
	return standardconfig.PostgresBlock{
		fakeKey(key): {
			Host:     "postgres.invalid",
			Port:     5432,
			Database: "app",
			Username: "app",
			Password: "",
			SSL:      true,
			Pool:     standardconfig.PoolSizing{Min: 0, Max: 10},
		},
	}
}

// FakeCache returns a container-free cache block for unit tiers.
func FakeCache(key string) standardconfig.CacheBlock {
	return standardconfig.CacheBlock{fakeKey(key): fakeRedis("cache.invalid")}
}

// FakeKv returns a container-free kv block for unit tiers.
//
// It addresses a different host from [FakeCache] so a test that accidentally
// wires the cache block where kv belongs fails on the address rather than
// passing quietly.
func FakeKv(key string) standardconfig.KvBlock {
	return standardconfig.KvBlock{fakeKey(key): fakeRedis("kv.invalid")}
}

// FakeStorage returns a container-free storage block for unit tiers.
func FakeStorage(key string) standardconfig.StorageBlock {
	return standardconfig.StorageBlock{
		fakeKey(key): {
			Endpoint:        "https://storage.invalid",
			Region:          "us-east-1",
			Bucket:          "app",
			AccessKeyID:     "",
			SecretAccessKey: "",
			ForcePathStyle:  false,
		},
	}
}

// fakeRedis builds the Redis-protocol entry both fake blocks share.
func fakeRedis(host string) standardconfig.RedisEntry {
	return standardconfig.RedisEntry{
		Host:     host,
		Port:     6379,
		Password: "",
		DB:       0,
		TLS:      true,
	}
}

// fakeKey defaults a blank connection name to [DefaultKey], so a caller that
// does not care about the name does not have to invent one.
func fakeKey(key string) string {
	return valueOr(key, DefaultKey)
}
