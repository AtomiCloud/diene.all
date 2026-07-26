package redis

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// TokenStore adapts a persistent Redis client to authengine.TokenStore.
type TokenStore struct {
	client *Client
}

// NewTokenStore constructs a Redis-backed auth token store.
func NewTokenStore(client *Client) (*TokenStore, error) {
	if client == nil {
		return nil, errors.New("redis token store: client is required")
	}
	return &TokenStore{client: client}, nil
}

// Get retrieves and decodes one cached access token.
func (s *TokenStore) Get(ctx context.Context, key string) (authengine.AccessToken, bool, error) {
	encoded, found, err := s.client.Get(ctx, key)
	if err != nil || !found {
		return authengine.AccessToken{}, found, err
	}
	var token authengine.AccessToken
	if err := json.Unmarshal([]byte(encoded), &token); err != nil {
		return authengine.AccessToken{}, false, fmt.Errorf("redis token store: decode token: %w", err)
	}
	return token, true, nil
}

// Set encodes and stores one access token for ttl.
func (s *TokenStore) Set(
	ctx context.Context,
	key string,
	token authengine.AccessToken,
	ttl time.Duration,
) error {
	encoded, err := json.Marshal(token)
	if err != nil {
		return fmt.Errorf("redis token store: encode token: %w", err)
	}
	return s.client.Set(ctx, key, encoded, ttl)
}

// Delete removes one cached access token.
func (s *TokenStore) Delete(ctx context.Context, key string) error {
	_, err := s.client.Delete(ctx, key)
	return err
}
