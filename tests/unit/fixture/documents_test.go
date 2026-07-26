package fixture_test

import (
	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

// The documents below are the shapes the composed preview root schema actually
// validates. They are written out rather than reflected from the engine structs
// so a schema change in a published sibling shows up here as a failing load —
// which is the point of loading a fixture through the real validator at all.

// otelDocument is a full-defaults otel block with every signal off, i.e. the D2
// off-by-default posture a base layer carries.
func otelDocument() map[string]any {
	return map[string]any{
		"logs":    map[string]any{"enabled": false, "exporter": exporterDocument()},
		"metrics": map[string]any{"enabled": false, "exporter": exporterDocument(), "interval": otel.DefaultMetricInterval},
		"traces": map[string]any{
			"enabled":  false,
			"exporter": exporterDocument(),
			"sampler":  map[string]any{"type": string(otel.SamplerParentBasedTraceIDRatio), "ratio": otel.DefaultSamplerRatio},
		},
	}
}

// exporterDocument is the shared per-signal exporter fragment.
func exporterDocument() map[string]any {
	return map[string]any{
		"console": map[string]any{"enabled": false},
		"otlp": map[string]any{
			"enabled":  false,
			"endpoint": "",
			"protocol": otel.ProtocolHTTPProtobuf,
			"headers":  map[string]any{"x-atomi-preview": "harness"},
			"timeout":  otel.DefaultExportTimeout,
		},
	}
}

// authDocument is a full-defaults auth-engine block with blank secrets, which
// the environment layer injects.
func authDocument() map[string]any {
	return map[string]any{
		"idp": map[string]any{
			"issuer":           "https://logto.garden.invalid/oidc",
			"audience":         "https://billing.garden.invalid",
			"jwksUri":          "https://logto.garden.invalid/oidc/jwks",
			"algorithms":       []any{"RS256"},
			"clockSkewSeconds": 60,
			"management": map[string]any{
				"endpoint": "https://logto.garden.invalid/api",
				"resource": "https://logto.garden.invalid/api",
				"clientId": "management",
				// Blank in YAML, injected through the environment (M4/M33).
				"clientSecret": "",
			},
		},
		//nolint:gosec // a fixture document: every secret here is deliberately blank
		"minting": map[string]any{
			"tokenEndpoint":      "https://logto.garden.invalid/oidc/token",
			"clientId":           "billing",
			"clientSecret":       "",
			"handoffPath":        "/app-handoff",
			"cacheNamespace":     "auth-token",
			"refreshSkewSeconds": 30,
			"concurrency":        4,
		},
		"resources": []any{map[string]any{
			"name":      "primary",
			"indicator": "https://billing.garden.invalid",
			"scopes":    []any{},
		}},
		"policies": map[string]any{},
	}
}

// apiDocument is a full-defaults api-engine block with one backend.
func apiDocument(baseURL string) map[string]any {
	return map[string]any{
		"backends": map[string]any{"primary": map[string]any{
			"baseUrl":   baseURL,
			"resource":  "primary",
			"indicator": baseURL,
			"scopes":    []any{},
			"timeout":   apiengine.DefaultTimeout.String(),
		}},
		"retry": map[string]any{
			"network": true,
			"delay":   apiengine.DefaultConfig().Retry.Delay.String(),
		},
	}
}
