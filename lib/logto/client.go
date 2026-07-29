package logto

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// Doer performs the adapter's HTTP round trips. *http.Client satisfies it; a test
// binds a recording double or an httptest-backed client.
type Doer interface {
	// Do performs request and returns its response.
	Do(request *http.Request) (*http.Response, error)
}

// ClientOptions configures a [Client].
type ClientOptions struct {
	// Config is the engine configuration block this adapter reads its endpoints
	// and credentials from.
	Config authengine.Config
	// HTTP performs the round trips. Nil uses http.DefaultClient.
	HTTP Doer
	// Problems mints problem-typed failures.
	Problems *authengine.Problems
	// Clock is the injected time seam, used to turn the provider's relative
	// expires_in into an absolute expiry.
	Clock interfaces.System
}

// Client is the Logto implementation of the auth-engine provider seam.
//
// It converts between Logto's OAuth wire shapes and the engine's domain types, and
// it is the ONLY place in this module that speaks HTTP to an identity provider. Two
// conversions are load-bearing: the provider reports a relative `expires_in`, which
// this adapter turns into an absolute instant off the injected clock so caching is
// testable, and the provider reports failures as OAuth error documents, which this
// adapter turns into the engine's problem vocabulary so a caller never has to parse
// a provider-specific body.
type Client struct {
	config   authengine.Config
	http     Doer
	problems *authengine.Problems
	clock    interfaces.System
}

// NewClient creates the Logto adapter, rejecting a configuration missing the
// endpoints it needs.
func NewClient(options ClientOptions) (Client, error) {
	if options.Problems == nil {
		return Client{}, errors.New("auth-engine logto client requires a problem factory")
	}
	if options.Clock == nil {
		return Client{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a clock seam is required so token expiry stays injectable", nil)
	}
	if options.Config.Minting.TokenEndpoint == "" {
		return Client{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a token endpoint is required to mint tokens", nil)
	}
	transport := options.HTTP
	if transport == nil {
		transport = http.DefaultClient
	}
	return Client{
		config:   options.Config,
		http:     transport,
		problems: options.Problems,
		clock:    options.Clock,
	}, nil
}

// ResourceToken exchanges a session's refresh token for a token scoped to one
// resource. This is the per-resource token path: one round trip per resource, with
// the resource indicator and its scopes on the request.
func (c Client) ResourceToken(
	ctx context.Context,
	request authengine.ResourceTokenRequest,
) (authengine.AccessToken, error) {
	if request.RefreshToken == "" {
		return authengine.AccessToken{}, c.problems.Raise(authengine.ProblemRefreshTokenUnknown,
			"a blank refresh token cannot be exchanged", nil)
	}
	form := url.Values{}
	form.Set("grant_type", "refresh_token")
	form.Set("refresh_token", request.RefreshToken)
	form.Set("resource", request.Resource.Indicator)
	if len(request.Resource.Scopes) > 0 {
		form.Set("scope", strings.Join(request.Resource.Scopes, " "))
	}

	granted, err := c.token(ctx, form)
	if err != nil {
		return authengine.AccessToken{}, err
	}
	return c.accessToken(granted, request.Resource)
}

// ClientCredentials mints a machine-to-machine token for one resource.
func (c Client) ClientCredentials(
	ctx context.Context,
	request authengine.ClientCredentialsRequest,
) (authengine.AccessToken, error) {
	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("resource", request.Resource.Indicator)
	if len(request.Resource.Scopes) > 0 {
		form.Set("scope", strings.Join(request.Resource.Scopes, " "))
	}

	granted, err := c.token(ctx, form)
	if err != nil {
		return authengine.AccessToken{}, err
	}
	return c.accessToken(granted, request.Resource)
}

// Refresh rotates a session's refresh token, returning the replacement pair.
//
// A provider that returns no replacement refresh token is not rotating, so the
// presented token is carried forward rather than silently dropped — losing it would
// end the session on the next refresh.
func (c Client) Refresh(ctx context.Context, refreshToken string) (authengine.Session, error) {
	if refreshToken == "" {
		return authengine.Session{}, c.problems.Raise(authengine.ProblemRefreshTokenUnknown,
			"a blank refresh token cannot be rotated", nil)
	}
	form := url.Values{}
	form.Set("grant_type", "refresh_token")
	form.Set("refresh_token", refreshToken)

	granted, err := c.token(ctx, form)
	if err != nil {
		return authengine.Session{}, err
	}
	access, err := c.accessToken(granted, authengine.Resource{})
	if err != nil {
		return authengine.Session{}, err
	}
	rotated := granted.RefreshToken
	if rotated == "" {
		rotated = refreshToken
	}
	return authengine.Session{
		Access:           access,
		RefreshToken:     rotated,
		RefreshExpiresAt: access.IssuedAt.Add(authengine.RefreshTokenLifetime),
	}, nil
}

// MintOneTimeToken mints a single-use login token, used when a deferred deep-link
// nonce is redeemed.
func (c Client) MintOneTimeToken(
	ctx context.Context,
	request authengine.OneTimeTokenRequest,
) (authengine.OneTimeToken, error) {
	if request.Subject == "" {
		return authengine.OneTimeToken{}, c.problems.Raise(authengine.ProblemTokenClaimMissing,
			"a one-time token must be minted for a known subject",
			map[string]any{"claim": authengine.ClaimSubject})
	}
	body := map[string]any{
		"userId":    request.Subject,
		"expiresIn": int(authengine.OneTimeTokenLifetime.Seconds()),
	}
	if request.Email != nil {
		body["email"] = *request.Email
	}

	now, err := c.now()
	if err != nil {
		return authengine.OneTimeToken{}, err
	}
	var minted oneTimeTokenResponse
	if err := c.management(ctx, http.MethodPost, "/api/one-time-tokens", body, &minted); err != nil {
		return authengine.OneTimeToken{}, err
	}
	if minted.Token == "" {
		return authengine.OneTimeToken{}, c.problems.Raise(authengine.ProblemProviderUnavailable,
			"the identity provider returned no one-time token", nil)
	}
	return authengine.OneTimeToken{
		Value:     minted.Token,
		ExpiresAt: now.Add(authengine.OneTimeTokenLifetime),
	}, nil
}

// SetClaim writes a custom-data claim back onto the identity-provider user.
//
// This is the OnboardSync write-back: it patches the user's custom data, which the
// provider's JWT customizer then emits onto issued tokens. The value is written as
// given; the family convention is the string "true" for a registration claim.
func (c Client) SetClaim(ctx context.Context, subject string, name string, value any) error {
	if subject == "" || name == "" {
		return c.problems.Raise(authengine.ProblemTokenClaimMissing,
			"a claim write-back needs both a subject and a claim name",
			map[string]any{"subject": subject, "claim": name})
	}
	body := map[string]any{"customData": map[string]any{name: value}}
	return c.management(ctx, http.MethodPatch, "/api/users/"+url.PathEscape(subject)+"/custom-data", body, nil)
}

// tokenResponse is the OAuth token endpoint's success document.
type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	Scope        string `json:"scope"`
}

// oneTimeTokenResponse is the management API's one-time-token document.
type oneTimeTokenResponse struct {
	Token string `json:"token"`
}

// token posts a form to the OAuth token endpoint.
func (c Client) token(ctx context.Context, form url.Values) (tokenResponse, error) {
	form.Set("client_id", c.config.Minting.ClientID)
	request, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.config.Minting.TokenEndpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return tokenResponse{}, c.problems.RaiseFrom(authengine.ProblemConfigInvalid, err,
			"the configured token endpoint is not a usable URL",
			map[string]any{"endpoint": c.config.Minting.TokenEndpoint})
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if c.config.Minting.ClientSecret != "" {
		request.SetBasicAuth(c.config.Minting.ClientID, c.config.Minting.ClientSecret)
	}

	var granted tokenResponse
	if err := c.send(request, &granted); err != nil {
		return tokenResponse{}, err
	}
	if granted.AccessToken == "" {
		return tokenResponse{}, c.problems.Raise(authengine.ProblemProviderUnavailable,
			"the identity provider returned no access token", nil)
	}
	return granted, nil
}

// management calls the provider's management API, authenticating with a
// client-credentials token minted for the management resource.
func (c Client) management(
	ctx context.Context,
	method string,
	path string,
	body map[string]any,
	into any,
) error {
	management := c.config.IDP.Management
	if management.Endpoint == "" {
		return c.problems.Raise(authengine.ProblemConfigInvalid,
			"a management endpoint is required to write claims back", nil)
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return c.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the management request body could not be encoded", nil)
	}
	token, err := c.ClientCredentials(ctx, authengine.ClientCredentialsRequest{
		Resource: authengine.Resource{Name: "management", Indicator: management.Resource},
	})
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, method,
		strings.TrimSuffix(management.Endpoint, "/")+path, strings.NewReader(string(encoded)))
	if err != nil {
		return c.problems.RaiseFrom(authengine.ProblemConfigInvalid, err,
			"the configured management endpoint is not a usable URL",
			map[string]any{"endpoint": management.Endpoint})
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer "+token.Value)
	return c.send(request, into)
}

// send performs one round trip, decoding a success document into into and turning
// any non-2xx response into the engine's problem vocabulary.
func (c Client) send(request *http.Request, into any) error {
	response, err := c.http.Do(request)
	if err != nil {
		return c.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the identity provider could not be reached",
			map[string]any{"url": request.URL.String()})
	}
	defer func() { _ = response.Body.Close() }()

	payload, err := io.ReadAll(response.Body)
	if err != nil {
		return c.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the identity provider response could not be read", nil)
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return c.problems.Raise(classifyStatus(response.StatusCode),
			"the identity provider rejected the request",
			map[string]any{
				"status": response.StatusCode,
				"body":   strings.TrimSpace(string(payload)),
			})
	}
	if into == nil {
		return nil
	}
	if err := json.Unmarshal(payload, into); err != nil {
		return c.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the identity provider response was not the expected document",
			map[string]any{"status": strconv.Itoa(response.StatusCode)})
	}
	return nil
}

// classify maps a provider status onto the engine's problem vocabulary, so a
// caller distinguishes "our credentials are wrong" from "the provider is down"
// without reading a provider-specific body.
func classifyStatus(status int) string {
	switch status {
	case http.StatusUnauthorized:
		return authengine.ProblemTokenSignatureInvalid
	case http.StatusForbidden:
		return authengine.ProblemOwnershipDenied
	default:
		return authengine.ProblemProviderUnavailable
	}
}

// accessToken converts a provider grant into the engine's absolute-expiry token.
func (c Client) accessToken(
	granted tokenResponse,
	resource authengine.Resource,
) (authengine.AccessToken, error) {
	now, err := c.now()
	if err != nil {
		return authengine.AccessToken{}, err
	}
	lifetime := time.Duration(granted.ExpiresIn) * time.Second
	if granted.ExpiresIn <= 0 {
		lifetime = authengine.AccessTokenLifetime
	}
	scopes := resource.Scopes
	if granted.Scope != "" {
		scopes = strings.Fields(granted.Scope)
	}
	return authengine.AccessToken{
		Value:     granted.AccessToken,
		Resource:  resource.Name,
		Scopes:    scopes,
		IssuedAt:  now,
		ExpiresAt: now.Add(lifetime),
	}, nil
}

// now reads the injected clock as a problem-typed operation.
func (c Client) now() (time.Time, error) {
	now, err := c.clock.NowUTC()
	if err != nil {
		return time.Time{}, c.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the clock seam could not supply the current instant", nil)
	}
	return now, nil
}
