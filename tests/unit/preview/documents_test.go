package preview_test

import (
	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	presetth "github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// The documents below feed the permanent compose-and-validate gate. They are
// written out as the shapes the published engine schemas actually accept rather
// than reflected from the Go structs, because reflecting from the same structs
// the schema was generated from would make the gate agree with itself.
//
// The preset document is taken from the standard-config sibling's own fake so the
// infra half of the gate cannot drift from the preset contract.

// appDocument is the C0 §3 service-tree block.
func appDocument() map[string]any {
	return map[string]any{
		"landscape": "garden",
		"platform":  "sulfoxide",
		"service":   "billing",
		"module":    "core",
		"version":   "1.0.0",
	}
}

// otelDocument is a full-defaults otel block with every signal off — the D2
// off-by-default posture a base layer carries.
func otelDocument() map[string]any {
	return map[string]any{
		"logs":    map[string]any{"enabled": false, "exporter": exporterDocument()},
		"metrics": map[string]any{"enabled": false, "exporter": exporterDocument(), "interval": otel.DefaultMetricInterval},
		"traces": map[string]any{
			"enabled":  false,
			"exporter": exporterDocument(),
			"sampler": map[string]any{
				"type":  string(otel.SamplerParentBasedTraceIDRatio),
				"ratio": otel.DefaultSamplerRatio,
			},
		},
	}
}

// exporterDocument is the per-signal exporter fragment the three signals share.
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

// authDocument is a full-defaults auth-engine block. Every secret is blank in the
// document and injected through the environment layer (M4/M33).
func authDocument() map[string]any {
	return map[string]any{
		"idp": map[string]any{
			"issuer":           "https://logto.garden.invalid/oidc",
			"audience":         "https://billing.garden.invalid",
			"jwksUri":          "https://logto.garden.invalid/oidc/jwks",
			"algorithms":       []any{"RS256"},
			"clockSkewSeconds": 60,
			"management": map[string]any{
				"endpoint":     "https://logto.garden.invalid/api",
				"resource":     "https://logto.garden.invalid/api",
				"clientId":     "management",
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

// apiDocument is a full-defaults api-engine block with one registered backend.
//
// Its two duration fields are the ones whose schema `pattern` used to be
// uncompilable by Go's regexp, which is the whole reason the gate above exists.
func apiDocument() map[string]any {
	return map[string]any{
		"backends": map[string]any{"primary": map[string]any{
			"baseUrl":   "https://billing.garden.invalid",
			"resource":  "primary",
			"indicator": "https://billing.garden.invalid",
			"scopes":    []any{},
			"timeout":   apiengine.DefaultTimeout.String(),
		}},
		"retry": map[string]any{
			"network": true,
			"delay":   apiengine.DefaultConfig().Retry.Delay.String(),
		},
	}
}

// postgresDocument is the standard-config sibling's own fake preset block, so the
// infra half of the gate is pinned to the preset contract rather than to a local
// guess about it.
func postgresDocument() map[string]any {
	entry := presetth.FakePostgres(presetth.DefaultKey)[presetth.DefaultKey]
	return map[string]any{
		presetth.DefaultKey: map[string]any{
			"host":     entry.Host,
			"port":     entry.Port,
			"database": entry.Database,
			"username": entry.Username,
			"password": entry.Password,
			"ssl":      entry.SSL,
			"pool":     map[string]any{"min": entry.Pool.Min, "max": entry.Pool.Max},
		},
	}
}
