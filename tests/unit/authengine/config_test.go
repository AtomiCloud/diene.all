package authengine_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// sampleConfig is the engine block as a service would compose it.
func sampleConfig() authengine.Config {
	return authengine.Config{
		IDP: authengine.IDPConfig{
			Issuer:   "https://api.lithium.alcohol.mew.cluster.atomi.cloud",
			Audience: "alcohol-zinc",
			JWKSURI:  "https://api.lithium.alcohol.mew.cluster.atomi.cloud/oidc/jwks",
			Management: authengine.ManagementConfig{
				Endpoint: "https://api.lithium.alcohol.mew.cluster.atomi.cloud",
				Resource: "https://management.invalid",
				ClientID: "management-app",
			},
		},
		Minting: authengine.MintingConfig{ //nolint:gosec // endpoint URLs and a client id, no credentials
			TokenEndpoint: "https://api.lithium.alcohol.mew.cluster.atomi.cloud/oidc/token",
			ClientID:      "zinc",
		},
		Resources: []authengine.ResourceConfig{
			{Name: "alcohol-zinc", Indicator: "https://api.zinc.invalid", Scopes: []string{"read:booking"}},
		},
		Policies: authengine.PolicySet{
			"OnlyAdmin": {Kind: authengine.PolicyAll, Field: authengine.ClaimRoles, Target: []string{"admin"}},
		},
	}
}

func TestConfigBlockKeyIsStable(t *testing.T) {
	t.Parallel()

	if authengine.ConfigBlockKey != "auth" {
		t.Fatalf("the composed root key is frozen family-wide, got %q", authengine.ConfigBlockKey)
	}
}

func TestConfigRoundTripsThroughItsWireForm(t *testing.T) {
	t.Parallel()

	encoded, err := json.Marshal(sampleConfig())
	requireNoError(t, err)

	var decoded authengine.Config
	requireNoError(t, json.Unmarshal(encoded, &decoded))

	if decoded.IDP.Issuer != sampleConfig().IDP.Issuer {
		t.Fatalf("expected the issuer to round-trip, got %q", decoded.IDP.Issuer)
	}
	if decoded.IDP.JWKSURI == "" || decoded.Minting.TokenEndpoint == "" {
		t.Fatalf("expected the endpoints to round-trip, got %+v", decoded)
	}
	if len(decoded.Resources) != 1 || decoded.Resources[0].Name != "alcohol-zinc" {
		t.Fatalf("expected the resource tree to round-trip, got %+v", decoded.Resources)
	}
	if declared, found := decoded.Policies["OnlyAdmin"]; !found || declared.Kind != authengine.PolicyAll {
		t.Fatalf("expected the policies to round-trip, got %+v", decoded.Policies)
	}
	// The secrets are blank in every committed layer and must stay blank on the way
	// through: the secret store injects them at runtime.
	if decoded.Minting.ClientSecret != "" || decoded.IDP.Management.ClientSecret != "" {
		t.Fatal("expected the committed configuration to carry no secrets")
	}
}

func TestConfigFallsBackToTheFamilyDefaults(t *testing.T) {
	t.Parallel()

	blank := authengine.Config{}

	if blank.IDP.Leeway() != authengine.DefaultClockSkew {
		t.Fatalf("expected the default clock skew, got %s", blank.IDP.Leeway())
	}
	if blank.Minting.Skew() != authengine.DefaultRefreshSkew {
		t.Fatalf("expected the default refresh skew, got %s", blank.Minting.Skew())
	}
	if blank.Minting.Mount() != authengine.DefaultHandoffPath {
		t.Fatalf("expected the default handoff mount, got %q", blank.Minting.Mount())
	}
}

func TestConfigHonoursExplicitOverrides(t *testing.T) {
	t.Parallel()

	configured := authengine.Config{
		IDP:     authengine.IDPConfig{ClockSkewSeconds: 5},
		Minting: authengine.MintingConfig{RefreshSkewSeconds: 7, HandoffPath: "/handoff"},
	}

	if configured.IDP.Leeway() != 5*time.Second {
		t.Fatalf("expected a five-second leeway, got %s", configured.IDP.Leeway())
	}
	if configured.Minting.Skew() != 7*time.Second {
		t.Fatalf("expected a seven-second skew, got %s", configured.Minting.Skew())
	}
	if configured.Minting.Mount() != "/handoff" {
		t.Fatalf("expected the configured mount, got %q", configured.Minting.Mount())
	}
}

func TestConfigTreeAppliesResourceValidation(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)

	tree, err := sampleConfig().Tree(problems)
	requireNoError(t, err)
	if names := tree.Names(); len(names) != 1 || names[0] != "alcohol-zinc" {
		t.Fatalf("expected the configured resource, got %v", names)
	}

	broken := sampleConfig()
	broken.Resources = append(broken.Resources, authengine.ResourceConfig{Name: "alcohol-zinc", Indicator: "x"})
	requireProblem(t, second(broken.Tree(problems)), authengine.ProblemConfigInvalid)
}

func TestConfigBlockSchemaDescribesTheBlock(t *testing.T) {
	t.Parallel()

	schema := authengine.ConfigBlockSchema()

	closed, isBool := schema["additionalProperties"].(bool)
	if schema["type"] != "object" || !isBool || closed {
		t.Fatalf("expected a closed object schema, got %v", schema)
	}
	properties, ok := schema["properties"].(map[string]any)
	if !ok {
		t.Fatalf("expected a properties map, got %v", schema["properties"])
	}
	for _, key := range []string{"idp", "minting", "resources", "policies"} {
		if _, found := properties[key]; !found {
			t.Fatalf("expected the schema to describe %q, got %v", key, properties)
		}
	}

	idp, ok := properties["idp"].(map[string]any)
	if !ok {
		t.Fatalf("expected an idp sub-schema, got %v", properties["idp"])
	}
	required, ok := idp["required"].([]any)
	if !ok || len(required) != 2 {
		t.Fatalf("expected the issuer and JWKS URI to be required, got %v", idp["required"])
	}

	// The schema must be serializable: the CONFIG library validates a service's
	// composed root document, so a fragment that cannot be encoded is useless.
	if _, err := json.Marshal(schema); err != nil {
		t.Fatalf("expected the schema fragment to encode, got %v", err)
	}
}

func TestConfigBlockSchemaCarriesNoLifetimeKnobs(t *testing.T) {
	t.Parallel()

	encoded, err := json.Marshal(authengine.ConfigBlockSchema())
	requireNoError(t, err)

	// The token lifetimes are contract constants, not configuration: a service that
	// could tune them would diverge from the family silently.
	for _, forbidden := range []string{"accessTokenLifetime", "refreshTokenLifetime", "expiresIn", "nonceTtl"} {
		if contains(string(encoded), forbidden) {
			t.Fatalf("the schema must not expose %q as a knob", forbidden)
		}
	}
}

// contains reports whether haystack contains needle.
func contains(haystack string, needle string) bool {
	return len(haystack) >= len(needle) && indexOf(haystack, needle) >= 0
}

// indexOf returns the first index of needle in haystack, or -1.
func indexOf(haystack string, needle string) int {
	for index := 0; index+len(needle) <= len(haystack); index++ {
		if haystack[index:index+len(needle)] == needle {
			return index
		}
	}
	return -1
}
