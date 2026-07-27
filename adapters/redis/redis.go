// Package redis adapts go-redis clients to cache, kv, and reachability ports.
package redis

import (
	"context"
	"crypto/tls"
	"errors"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	goredis "github.com/redis/go-redis/v9"
)

// CommandAPI is the go-redis command surface used by Client.
type CommandAPI interface {
	Ping(ctx context.Context) *goredis.StatusCmd
	Get(ctx context.Context, key string) *goredis.StringCmd
	Set(ctx context.Context, key string, value any, expiration time.Duration) *goredis.StatusCmd
	SetNX(ctx context.Context, key string, value any, expiration time.Duration) *goredis.BoolCmd
	Del(ctx context.Context, keys ...string) *goredis.IntCmd
	Close() error
}

// Client is an instrumented Redis-protocol connection.
type Client struct {
	commands CommandAPI
	native   goredis.UniversalClient
	tracer   *tracing.Tracer
}

// Open constructs a go-redis client from a standard-config cache or kv entry.
func Open(entry standardconfig.RedisEntry, tracer *tracing.Tracer) (*Client, error) {
	if err := validateEntry(entry); err != nil {
		return nil, err
	}
	options := &goredis.Options{
		Addr:     net.JoinHostPort(entry.Host, strconv.Itoa(entry.Port)),
		Password: entry.Password,
		DB:       entry.DB,
	}
	if entry.TLS {
		options.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	driver := goredis.NewClient(options)
	client, err := newClient(driver, driver, tracer)
	if err != nil {
		_ = driver.Close()
		return nil, err
	}
	return client, nil
}

// New wraps an existing go-redis-compatible command client.
func New(commands CommandAPI, tracer *tracing.Tracer) (*Client, error) {
	return newClient(commands, nil, tracer)
}

func newClient(commands CommandAPI, native goredis.UniversalClient, tracer *tracing.Tracer) (*Client, error) {
	if commands == nil {
		return nil, errors.New("redis: command client is required")
	}
	if tracer == nil {
		return nil, errors.New("redis: tracer is required")
	}
	return &Client{commands: commands, native: native, tracer: tracer}, nil
}

// Native returns the underlying universal client when Client was built by Open.
func (c *Client) Native() goredis.UniversalClient {
	return c.native
}

// Ping checks Redis reachability.
func (c *Client) Ping(ctx context.Context) error {
	span, err := c.tracer.Start("redis.ping", nil)
	if err != nil {
		return err
	}
	return span.End(c.commands.Ping(ctx).Err())
}

// Get retrieves key, distinguishing absence from an empty stored value.
func (c *Client) Get(ctx context.Context, key string) (string, bool, error) {
	if strings.TrimSpace(key) == "" {
		return "", false, errors.New("redis: key is required")
	}
	span, err := c.tracer.Start("redis.get", map[string]any{"db.key": key})
	if err != nil {
		return "", false, err
	}
	value, operationErr := c.commands.Get(ctx, key).Result()
	if errors.Is(operationErr, goredis.Nil) {
		if endErr := span.End(nil); endErr != nil {
			return "", false, endErr
		}
		return "", false, nil
	}
	if endErr := span.End(operationErr); endErr != nil {
		return "", false, endErr
	}
	return value, true, nil
}

// Set stores value with an optional expiry. A zero expiry means no expiry.
func (c *Client) Set(ctx context.Context, key string, value any, expiry time.Duration) error {
	if strings.TrimSpace(key) == "" {
		return errors.New("redis: key is required")
	}
	if expiry < 0 {
		return errors.New("redis: expiry must not be negative")
	}
	span, err := c.tracer.Start("redis.set", map[string]any{"db.key": key})
	if err != nil {
		return err
	}
	return span.End(c.commands.Set(ctx, key, value, expiry).Err())
}

// SetIfAbsent stores value only when key does not exist.
func (c *Client) SetIfAbsent(ctx context.Context, key, value string) (bool, error) {
	if strings.TrimSpace(key) == "" {
		return false, errors.New("redis: key is required")
	}
	span, err := c.tracer.Start("redis.set_if_absent", map[string]any{"db.key": key})
	if err != nil {
		return false, err
	}
	stored, operationErr := c.commands.SetNX(ctx, key, value, 0).Result()
	if endErr := span.End(operationErr); endErr != nil {
		return false, endErr
	}
	return stored, nil
}

// Delete removes keys and returns the number of deleted entries.
func (c *Client) Delete(ctx context.Context, keys ...string) (int64, error) {
	if len(keys) == 0 {
		return 0, nil
	}
	for _, key := range keys {
		if strings.TrimSpace(key) == "" {
			return 0, errors.New("redis: keys must not be blank")
		}
	}
	span, err := c.tracer.Start("redis.delete", map[string]any{"db.key_count": int64(len(keys))})
	if err != nil {
		return 0, err
	}
	deleted, operationErr := c.commands.Del(ctx, keys...).Result()
	if endErr := span.End(operationErr); endErr != nil {
		return 0, endErr
	}
	return deleted, nil
}

// Close releases the underlying Redis connection resources.
func (c *Client) Close() error {
	return c.commands.Close()
}

func validateEntry(entry standardconfig.RedisEntry) error {
	switch {
	case strings.TrimSpace(entry.Host) == "":
		return errors.New("redis: host is required")
	case entry.Port < 1 || entry.Port > 65535:
		return errors.New("redis: port must be between 1 and 65535")
	case entry.DB < 0:
		return errors.New("redis: database index must not be negative")
	default:
		return nil
	}
}
