package authengine

import "context"

// SessionSource mints per-resource access tokens on behalf of one authenticated
// user session, exchanging the session's refresh token at the IdP.
type SessionSource struct {
	provider Provider
	session  Session
}

// NewSessionSource binds provider to session. The session is captured by value:
// a source is a per-session view, so rotating a refresh token yields a NEW source
// rather than mutating a shared one, which is what keeps rotation observable.
func NewSessionSource(provider Provider, session Session) SessionSource {
	return SessionSource{provider: provider, session: session}
}

// Session returns the session this source mints for.
func (s SessionSource) Session() Session {
	return s.session
}

// Mint exchanges the session's refresh token for a token scoped to resource.
func (s SessionSource) Mint(ctx context.Context, resource Resource) (AccessToken, error) {
	return s.provider.ResourceToken(ctx, ResourceTokenRequest{
		Subject:      s.session.Subject,
		RefreshToken: s.session.RefreshToken,
		Resource:     resource,
	})
}

// ClientCredentialsSource mints machine-to-machine access tokens for the client
// itself.
//
// This is the operator's flow: a workload with no user session still needs
// per-resource tokens for the backends it drives, and it gets them by
// authenticating as a client rather than by holding somebody's session. It lives
// in this library alongside server-side validation on purpose — the same resource
// tree, cache, and problem vocabulary serve both directions.
type ClientCredentialsSource struct {
	provider Provider
}

// NewClientCredentialsSource binds provider for machine-to-machine minting.
func NewClientCredentialsSource(provider Provider) ClientCredentialsSource {
	return ClientCredentialsSource{provider: provider}
}

// Mint requests a client-credentials token scoped to resource.
func (s ClientCredentialsSource) Mint(ctx context.Context, resource Resource) (AccessToken, error) {
	return s.provider.ClientCredentials(ctx, ClientCredentialsRequest{Resource: resource})
}
