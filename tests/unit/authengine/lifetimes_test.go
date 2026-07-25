package authengine_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

func TestTokenLifetimesMatchTheFamilyContract(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		value time.Duration
		want  time.Duration
	}{
		{name: "access token", value: authengine.AccessTokenLifetime, want: 10 * time.Minute},
		{name: "refresh token", value: authengine.RefreshTokenLifetime, want: 336 * time.Hour},
		{name: "deferred nonce", value: authengine.DeferredTokenLifetime, want: 15 * time.Minute},
		{name: "one-time token", value: authengine.OneTimeTokenLifetime, want: 120 * time.Second},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			if testCase.value != testCase.want {
				t.Fatalf("expected %s, got %s", testCase.want, testCase.value)
			}
		})
	}
}

func TestOneTimeTokenLifetimeIsNotTheAccessTokenLifetime(t *testing.T) {
	t.Parallel()

	if authengine.OneTimeTokenLifetime >= authengine.AccessTokenLifetime {
		t.Fatal("the deferred one-time token must stay far shorter than an access token")
	}
	if authengine.DefaultRefreshSkew >= authengine.AccessTokenLifetime {
		t.Fatal("the refresh skew must be a fraction of the access-token lifetime")
	}
	if authengine.DefaultClockSkew >= authengine.AccessTokenLifetime {
		t.Fatal("the clock skew must be a fraction of the access-token lifetime")
	}
}
