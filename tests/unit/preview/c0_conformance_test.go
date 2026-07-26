package preview_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/preview"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

// The harness addresses a real collector, so the endpoints it accepts must be
// exactly the C0 §4 set — no wider (a suite would silently export nowhere) and
// no narrower (a suite would refuse a deployment the runtime accepts). The
// vectors come from the published otel sibling's own pinned contract, so this
// test fails if either side drifts.

func TestPreviewAcceptsEveryC0ValidCollectorEndpoint(t *testing.T) {
	t.Parallel()

	if len(otel.C0Otel.ValidEndpoints) == 0 {
		t.Fatal("the C0 contract carries no valid endpoints, so this proves nothing")
	}
	for _, endpoint := range otel.C0Otel.ValidEndpoints {
		t.Run(endpoint, func(t *testing.T) {
			t.Parallel()
			target := resolveComplete(t, func(environment map[string]string) {
				environment[preview.EnvOtlpEndpoint] = endpoint
			})
			if target.OtlpEndpoint != endpoint {
				t.Fatalf("endpoint = %q, want %q", target.OtlpEndpoint, endpoint)
			}
			if got := target.OtelConfig().Traces.Exporter.Otlp.Endpoint; got != endpoint {
				t.Fatalf("exported endpoint = %q, want %q", got, endpoint)
			}
		})
	}
}

func TestPreviewRejectsEveryC0InvalidCollectorEndpoint(t *testing.T) {
	t.Parallel()

	if len(otel.C0Otel.InvalidEndpoints) == 0 {
		t.Fatal("the C0 contract carries no invalid endpoints, so this proves nothing")
	}
	for _, endpoint := range otel.C0Otel.InvalidEndpoints {
		t.Run(endpoint, func(t *testing.T) {
			t.Parallel()
			environment := completeEnvironment()
			environment[preview.EnvOtlpEndpoint] = endpoint
			_, err := preview.Resolve(systemWith(environment), requireProblems(t))
			if got := problemID(t, err); got != e2e.ProblemTargetIncomplete {
				t.Fatalf("problem id = %q, want %q", got, e2e.ProblemTargetIncomplete)
			}
			if problemData(t, err)["port"] != otel.OtlpHTTPPort {
				t.Fatalf("problem data = %v, want the C0 port named", problemData(t, err))
			}
		})
	}
}

func TestPreviewPinsTheC0ProtocolAndPort(t *testing.T) {
	t.Parallel()

	if otel.C0Otel.Protocol != otel.ProtocolHTTPProtobuf {
		t.Fatalf("C0 protocol = %q, want %q", otel.C0Otel.Protocol, otel.ProtocolHTTPProtobuf)
	}
	if otel.C0Otel.OtlpPort != otel.OtlpHTTPPort {
		t.Fatalf("C0 port = %q, want %q", otel.C0Otel.OtlpPort, otel.OtlpHTTPPort)
	}
	target := resolveComplete(t, nil)
	config := target.OtelConfig()
	signals := []string{config.Logs.Exporter.Otlp.Protocol, config.Metrics.Exporter.Otlp.Protocol, config.Traces.Exporter.Otlp.Protocol}
	for index, protocol := range signals {
		if protocol != otel.C0Otel.Protocol {
			t.Fatalf("signal %d protocol = %q, want the C0 protocol %q", index, protocol, otel.C0Otel.Protocol)
		}
	}
}
