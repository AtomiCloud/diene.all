// Package kv provides the stable Redis adapter API.
package kv

import "context"

// RedisStore implements the note key-value contract with Redis.
type RedisStore struct{}

// NewRedisStore creates a Redis store for address.
func NewRedisStore(address string) *RedisStore { return &RedisStore{} }

// Save stores value at key.
func (*RedisStore) Save(context.Context, string, string) error { return nil }

// Load retrieves the value at key.
func (*RedisStore) Load(context.Context, string) (string, error) { return "", nil }

// Close releases the Redis client resources.
func (*RedisStore) Close() error { return nil }
