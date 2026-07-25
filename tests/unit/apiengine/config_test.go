package apiengine_test

import (
	"encoding/json"
	"slices"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

func TestConfigBlockKeyAndDefaults(t *testing.T) {
	t.Parallel()

	if apiengine.ConfigBlockKey != "api" {
		t.Errorf("ConfigBlockKey = %q, want api", apiengine.ConfigBlockKey)
	}
	config := apiengine.DefaultConfig()
	if config.Backends == nil {
		t.Error("DefaultConfig: want an initialized backend map")
	}
	if !config.Retry.Network {
		t.Error("DefaultConfig: want the single network retry enabled")
	}
}

func TestConfigNamesAreSorted(t *testing.T) {
	t.Parallel()

	config := apiengine.DefaultConfig()
	for _, name := range []string{"zulu", "alpha", "mike"} {
		config.Backends[name] = apiengine.BackendConfig{BaseURL: "https://x.invalid"}
	}
	// Map order is random in Go, so anything enumerating backends must sort or
	// two runs disagree.
	if got := config.Names(); !slices.Equal(got, []string{"alpha", "mike", "zulu"}) {
		t.Errorf("Names() = %v, want sorted order", got)
	}
}

func TestConfigResourceDefaultsToBackendName(t *testing.T) {
	t.Parallel()

	config := apiengine.DefaultConfig()
	config.Backends["plain"] = apiengine.BackendConfig{BaseURL: "https://x.invalid"}
	config.Backends["blank"] = apiengine.BackendConfig{BaseURL: "https://x.invalid", Resource: "   "}
	config.Backends["named"] = apiengine.BackendConfig{BaseURL: "https://x.invalid", Resource: "other"}

	if got := config.Resource("plain"); got != "plain" {
		t.Errorf("Resource(plain) = %q, want plain", got)
	}
	if got := config.Resource("blank"); got != "blank" {
		t.Errorf("Resource(blank) = %q, want the backend name for a blank override", got)
	}
	if got := config.Resource("named"); got != "other" {
		t.Errorf("Resource(named) = %q, want other", got)
	}
	if got := config.Resource("absent"); got != "absent" {
		t.Errorf("Resource(absent) = %q, want the name back", got)
	}
}

func TestBackendRequestTimeout(t *testing.T) {
	t.Parallel()

	unset := apiengine.BackendConfig{}
	if got := unset.RequestTimeout(); got != apiengine.DefaultTimeout.Std() {
		t.Errorf("RequestTimeout() = %v, want the default %v", got, apiengine.DefaultTimeout.Std())
	}
	declared := apiengine.BackendConfig{Timeout: wire.Duration(5 * time.Second)}
	if got := declared.RequestTimeout(); got != 5*time.Second {
		t.Errorf("RequestTimeout() = %v, want 5s", got)
	}
}

func TestConfigValidate(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	t.Run("accepts a well-formed block", func(t *testing.T) {
		t.Parallel()
		config := apiengine.DefaultConfig()
		config.Backends["api"] = apiengine.BackendConfig{
			BaseURL: "https://api.example.com",
			Timeout: wire.Duration(time.Second),
		}
		config.Backends["plain"] = apiengine.BackendConfig{BaseURL: "http://localhost:8080"}
		if err := config.Validate(problems); err != nil {
			t.Errorf("Validate: unexpected error %v", err)
		}
	})

	t.Run("requires a problem factory", func(t *testing.T) {
		t.Parallel()
		if err := apiengine.DefaultConfig().Validate(nil); err == nil {
			t.Error("Validate(nil): want an error, got none")
		}
	})

	cases := []struct {
		name   string
		mutate func(apiengine.Config)
	}{
		{"a blank backend name", func(c apiengine.Config) {
			c.Backends[""] = apiengine.BackendConfig{BaseURL: "https://x.invalid"}
		}},
		{"a missing base URL", func(c apiengine.Config) {
			c.Backends["api"] = apiengine.BackendConfig{}
		}},
		{"a blank base URL", func(c apiengine.Config) {
			c.Backends["api"] = apiengine.BackendConfig{BaseURL: "   "}
		}},
		{"a relative base URL", func(c apiengine.Config) {
			c.Backends["api"] = apiengine.BackendConfig{BaseURL: "/v1"}
		}},
		{"a non-http scheme", func(c apiengine.Config) {
			c.Backends["api"] = apiengine.BackendConfig{BaseURL: "ftp://x.invalid"}
		}},
		{"a negative timeout", func(c apiengine.Config) {
			c.Backends["api"] = apiengine.BackendConfig{
				BaseURL: "https://x.invalid",
				Timeout: wire.Duration(-time.Second),
			}
		}},
	}
	for _, testCase := range cases {
		t.Run(testCase.name+" is rejected", func(t *testing.T) {
			t.Parallel()
			config := apiengine.DefaultConfig()
			testCase.mutate(config)
			err := config.Validate(problems)
			testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
				Title: "Api configuration invalid",
			})
		})
	}

	t.Run("a negative retry delay is rejected", func(t *testing.T) {
		t.Parallel()
		config := apiengine.DefaultConfig()
		config.Retry.Delay = wire.Duration(-time.Second)
		err := config.Validate(problems)
		testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
			Title: "Api configuration invalid",
		})
	})
}

// The config block is the ONE declaration the auth-engine resource tree is
// derived from, so the two can never drift into disagreeing lists.
func TestConfigTree(t *testing.T) {
	t.Parallel()

	authProblems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	if err != nil {
		t.Fatalf("auth problems: %v", err)
	}

	config := apiengine.DefaultConfig()
	config.Backends["alpha"] = apiengine.BackendConfig{
		BaseURL:   "https://alpha.invalid",
		Indicator: "https://alpha.invalid/api",
		Scopes:    []string{"read", "write"},
	}
	config.Backends["beta"] = apiengine.BackendConfig{
		BaseURL:   "https://beta.invalid",
		Resource:  "beta-service",
		Indicator: "https://beta.invalid/api",
	}
	// A backend needing no credentials is omitted: declaring it would ask the
	// IdP to mint tokens nobody attaches.
	config.Backends["public"] = apiengine.BackendConfig{BaseURL: "https://public.invalid"}

	tree, err := config.Tree(authProblems)
	if err != nil {
		t.Fatalf("Tree: %v", err)
	}
	if got := tree.Names(); !slices.Equal(got, []string{"alpha", "beta-service"}) {
		t.Errorf("Tree().Names() = %v, want only the credentialed backends", got)
	}

	resources := tree.Resources()
	if len(resources) != 2 {
		t.Fatalf("Resources() = %d, want 2", len(resources))
	}
	if resources[0].Indicator != "https://alpha.invalid/api" {
		t.Errorf("alpha indicator = %q", resources[0].Indicator)
	}
	if !slices.Equal(resources[0].Scopes, []string{"read", "write"}) {
		t.Errorf("alpha scopes = %v, want the configured scopes", resources[0].Scopes)
	}
}

func TestConfigBlockSchema(t *testing.T) {
	t.Parallel()

	schema := apiengine.ConfigBlockSchema()
	if schema["type"] != "object" {
		t.Errorf("schema type = %v, want object", schema["type"])
	}

	// The schema has to survive JSON encoding: a consumer composes it into its
	// own root schema and hands the whole document to the config lib.
	encoded, err := json.Marshal(schema)
	if err != nil {
		t.Fatalf("marshal schema: %v", err)
	}
	var round map[string]any
	if err := json.Unmarshal(encoded, &round); err != nil {
		t.Fatalf("unmarshal schema: %v", err)
	}

	properties, ok := round["properties"].(map[string]any)
	if !ok {
		t.Fatal("schema declares no properties")
	}
	for _, key := range []string{"backends", "retry"} {
		if _, found := properties[key]; !found {
			t.Errorf("schema omits the %q property", key)
		}
	}

	backends, ok := properties["backends"].(map[string]any)
	if !ok {
		t.Fatal("backends is not an object schema")
	}
	entry, ok := backends["additionalProperties"].(map[string]any)
	if !ok {
		t.Fatal("backends declares no per-backend schema")
	}
	entryProperties, ok := entry["properties"].(map[string]any)
	if !ok {
		t.Fatal("the per-backend schema declares no properties")
	}
	for _, key := range []string{"baseUrl", "resource", "indicator", "scopes", "timeout"} {
		if _, found := entryProperties[key]; !found {
			t.Errorf("the per-backend schema omits %q", key)
		}
	}
}

// The block round-trips through JSON with C0 §1 wire shapes, which is how a
// consumer's YAML/JSON config actually reaches this struct.
func TestConfigJSONRoundTrip(t *testing.T) {
	t.Parallel()

	const document = `{
	  "backends": {
	    "billing": {
	      "baseUrl": "https://billing.example.com",
	      "resource": "alcohol-zinc",
	      "indicator": "https://billing.example.com/api",
	      "scopes": ["read"],
	      "timeout": "PT10S"
	    }
	  },
	  "retry": { "network": true, "delay": "PT0.2S" }
	}`

	var config apiengine.Config
	if err := json.Unmarshal([]byte(document), &config); err != nil {
		t.Fatalf("unmarshal config: %v", err)
	}

	billing := config.Backends["billing"]
	if billing.BaseURL != "https://billing.example.com" {
		t.Errorf("baseUrl = %q", billing.BaseURL)
	}
	if billing.Timeout.Std() != 10*time.Second {
		t.Errorf("timeout = %v, want 10s", billing.Timeout.Std())
	}
	if config.Retry.Delay.Std() != 200*time.Millisecond {
		t.Errorf("retry delay = %v, want 200ms", config.Retry.Delay.Std())
	}
	if !config.Retry.Network {
		t.Error("retry network: want true")
	}

	// And back out again in the same wire shapes.
	encoded, err := json.Marshal(config)
	if err != nil {
		t.Fatalf("marshal config: %v", err)
	}
	var reread apiengine.Config
	if err := json.Unmarshal(encoded, &reread); err != nil {
		t.Fatalf("re-read config: %v", err)
	}
	if reread.Backends["billing"].Timeout != billing.Timeout {
		t.Error("timeout did not survive the round trip")
	}
}
