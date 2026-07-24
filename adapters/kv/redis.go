package kv

import (
	"context"

	"github.com/redis/go-redis/v9"
)

type RedisStore struct {
	client *redis.Client
}

func NewRedisStore(address string) *RedisStore {
	return &RedisStore{client: redis.NewClient(&redis.Options{Addr: address})}
}

func (store *RedisStore) Save(ctx context.Context, key string, value string) error {
	return store.client.Set(ctx, key, value, 0).Err()
}

func (store *RedisStore) Load(ctx context.Context, key string) (string, error) {
	return store.client.Get(ctx, key).Result()
}

func (store *RedisStore) Close() error {
	return store.client.Close()
}
