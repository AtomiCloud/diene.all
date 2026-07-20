package kv

import (
	"context"

	"github.com/redis/go-redis/v9"
)

// RedisStore implements the note key-value contract with Redis.
type RedisStore struct {
	client *redis.Client
}

// NewRedisStore creates a Redis store for address.
func NewRedisStore(address string) *RedisStore {
	return &RedisStore{client: redis.NewClient(&redis.Options{Addr: address})}
}

// Save stores value at key.
func (store *RedisStore) Save(ctx context.Context, key string, value string) error {
	return store.client.Set(ctx, key, value, 0).Err()
}

// Load retrieves the value at key.
func (store *RedisStore) Load(ctx context.Context, key string) (string, error) {
	return store.client.Get(ctx, key).Result()
}

// Close releases the Redis client resources.
func (store *RedisStore) Close() error {
	return store.client.Close()
}
