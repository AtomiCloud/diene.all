package logto_test

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/logto"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/MicahParks/jwkset"
)

// publishJWKS serves a real JWK Set containing one RSA public key, so the key
// source is exercised against genuine key material rather than a mock.
func publishJWKS(t *testing.T, keyID string) *httptest.Server {
	t.Helper()

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	requireNoError(t, err)

	published, err := jwkset.NewJWKFromKey(key.Public(), jwkset.JWKOptions{
		Metadata: jwkset.JWKMetadataOptions{KID: keyID},
	})
	requireNoError(t, err)

	storage := jwkset.NewMemoryStorage()
	requireNoError(t, storage.KeyWrite(context.Background(), published))
	document, err := storage.JSONPublic(context.Background())
	requireNoError(t, err)

	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writer.Header().Set("Content-Type", "application/json")
		_, _ = writer.Write(document)
	}))
	t.Cleanup(server.Close)
	return server
}

func TestRemoteJWKSResolvesAPublishedKey(t *testing.T) {
	t.Parallel()

	server := publishJWKS(t, "live-key")
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	keys, err := logto.NewRemoteJWKS(context.Background(), server.URL, problems)
	requireNoError(t, err)

	key, err := keys.Key(context.Background(), "live-key")
	requireNoError(t, err)
	if key == nil {
		t.Fatal("expected usable key material")
	}
}

func TestRemoteJWKSReportsAnUnpublishedKeyID(t *testing.T) {
	t.Parallel()

	server := publishJWKS(t, "live-key")
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	keys, err := logto.NewRemoteJWKS(context.Background(), server.URL, problems)
	requireNoError(t, err)

	// A key id the set does not publish is the ordinary post-rotation case, and it
	// must be reported rather than answered with a nil key.
	_, err = keys.Key(context.Background(), "rotated-away")
	requireProblem(t, err, authengine.ProblemSigningKeyUnknown)
}

func TestNewRemoteJWKSRejectsAnUnusableConfiguration(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	if _, missing := logto.NewRemoteJWKS(ctx, "https://idp.invalid/jwks", nil); missing == nil {
		t.Fatal("expected a key source without a problem factory to be rejected")
	}
	_, err = logto.NewRemoteJWKS(ctx, "", problems)
	requireProblem(t, err, authengine.ProblemConfigInvalid)
}

func TestNewRemoteJWKSFailsFastOnAnUnreadableSet(t *testing.T) {
	t.Parallel()

	// The first fetch happens in the constructor on purpose: a misconfigured JWKS
	// URI must fail at startup, not on the first request that needs a key.
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	_, err = logto.NewRemoteJWKS(context.Background(), "://not-a-uri", problems)
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestNewJWKSWrapsAPreparedStorage(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	if _, missing := logto.NewJWKS(nil, nil); missing == nil {
		t.Fatal("expected a wrapped set without a problem factory to be rejected")
	}
	_, err = logto.NewJWKS(nil, problems)
	requireProblem(t, err, authengine.ProblemConfigInvalid)

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	requireNoError(t, err)
	published, err := jwkset.NewJWKFromKey(key.Public(), jwkset.JWKOptions{
		Metadata: jwkset.JWKMetadataOptions{KID: "tuned"},
	})
	requireNoError(t, err)
	storage := jwkset.NewMemoryStorage()
	requireNoError(t, storage.KeyWrite(ctx, published))

	keys, err := logto.NewJWKS(storage, problems)
	requireNoError(t, err)

	resolved, err := keys.Key(ctx, "tuned")
	requireNoError(t, err)
	if resolved == nil {
		t.Fatal("expected usable key material from the prepared storage")
	}
}

func TestRemoteJWKSValidatesItsOwnKeySourceSeam(t *testing.T) {
	t.Parallel()

	server := publishJWKS(t, "live-key")
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	keys, err := logto.NewRemoteJWKS(context.Background(), server.URL, problems)
	requireNoError(t, err)

	// The point of the seam: a validator resolves keys from the real remote source
	// with no other change.
	var source authengine.VerificationKeys = keys
	resolved, err := source.Key(context.Background(), "live-key")
	requireNoError(t, err)
	if resolved == nil {
		t.Fatal("expected the seam to resolve real key material")
	}
}

// emptyStorage publishes a key id whose entry carries no key material, which is
// what a malformed or unsupported JWK looks like once the set has been parsed.
type emptyStorage struct {
	jwkset.Storage
}

func (emptyStorage) KeyRead(context.Context, string) (jwkset.JWK, error) {
	return jwkset.JWK{}, nil
}

func TestRemoteJWKSRefusesAKeyWithNoMaterial(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	keys, err := logto.NewJWKS(emptyStorage{Storage: jwkset.NewMemoryStorage()}, problems)
	requireNoError(t, err)

	// Handing a nil key to the JWT library would surface as an opaque parse failure
	// somewhere else; refusing here keeps the diagnosis where the fault is.
	_, err = keys.Key(context.Background(), "hollow")
	requireProblem(t, err, authengine.ProblemSigningKeyUnknown)
}
