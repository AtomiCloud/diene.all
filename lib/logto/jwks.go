package logto

import (
	"context"
	"crypto"
	"errors"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/MicahParks/jwkset"
)

// RemoteJWKS resolves verification keys from a remote JSON Web Key Set.
//
// Fetch caching, refresh, and unknown-key refetch are the JWKS library's DEFAULTS:
// the family deliberately mandates no minimum key lifetime and no retry floor, and
// accepts the theoretical mid-rotation blip that comes with that rather than
// fighting each language's SDK. Do not add a bespoke cache here.
type RemoteJWKS struct {
	storage  jwkset.Storage
	problems *authengine.Problems
}

// NewRemoteJWKS creates a key source reading the JWKS published at uri.
//
// The constructor performs the first fetch, so a misconfigured JWKS URI fails at
// startup rather than on the first request that needs a key.
func NewRemoteJWKS(
	ctx context.Context,
	uri string,
	problems *authengine.Problems,
) (RemoteJWKS, error) {
	if problems == nil {
		return RemoteJWKS{}, errors.New("auth-engine logto JWKS requires a problem factory")
	}
	if uri == "" {
		return RemoteJWKS{}, problems.Raise(authengine.ProblemConfigInvalid,
			"a JWKS URI is required to verify token signatures", nil)
	}
	storage, err := jwkset.NewDefaultHTTPClientCtx(ctx, []string{uri})
	if err != nil {
		return RemoteJWKS{}, problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the identity provider JWKS could not be read", map[string]any{"jwksUri": uri})
	}
	return RemoteJWKS{storage: storage, problems: problems}, nil
}

// NewJWKS wraps an already-constructed JWKS storage, for a consumer that needs to
// tune the library's client options itself.
func NewJWKS(storage jwkset.Storage, problems *authengine.Problems) (RemoteJWKS, error) {
	if problems == nil {
		return RemoteJWKS{}, errors.New("auth-engine logto JWKS requires a problem factory")
	}
	if storage == nil {
		return RemoteJWKS{}, problems.Raise(authengine.ProblemConfigInvalid,
			"a JWKS storage is required to verify token signatures", nil)
	}
	return RemoteJWKS{storage: storage, problems: problems}, nil
}

// Key returns the public verification key published for keyID, refreshing the set
// through the library's own unknown-key handling when it is not already cached.
func (j RemoteJWKS) Key(ctx context.Context, keyID string) (crypto.PublicKey, error) {
	published, err := j.storage.KeyRead(ctx, keyID)
	if err != nil {
		return nil, j.problems.RaiseFrom(authengine.ProblemSigningKeyUnknown, err,
			"the identity provider publishes no key for this key id",
			map[string]any{"keyId": keyID})
	}
	key := published.Key()
	if key == nil {
		return nil, j.problems.Raise(authengine.ProblemSigningKeyUnknown,
			"the published key carries no usable key material",
			map[string]any{"keyId": keyID})
	}
	return key, nil
}
