package otelsdk_test

import (
	"context"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func TestDefaultStableExporterFactories(t *testing.T) {
	t.Parallel()

	url := "https://collector.example:4318/v1/traces"
	timeout := time.Second
	settings := otel.OtlpSettings{
		URL:     &url,
		Headers: map[string]string{"authorization": "secret"},
		Timeout: &timeout,
	}
	for _, kind := range []otelsdk.ExporterKind{otelsdk.ExporterConsole, otelsdk.ExporterOtlp} {
		spanExporter, err := otelsdk.DefaultSpanExporterFactory(context.Background(), kind, settings)
		if err != nil || spanExporter == nil {
			t.Fatalf("span exporter %q: %v", kind, err)
		}
		if shutdownErr := spanExporter.Shutdown(context.Background()); shutdownErr != nil {
			t.Fatalf("shutdown span exporter %q: %v", kind, shutdownErr)
		}
		metricURL := "https://collector.example:4318/v1/metrics"
		settings.URL = &metricURL
		metricExporter, err := otelsdk.DefaultMetricExporterFactory(context.Background(), kind, settings)
		if err != nil || metricExporter == nil {
			t.Fatalf("metric exporter %q: %v", kind, err)
		}
		if err := metricExporter.Shutdown(context.Background()); err != nil {
			t.Fatalf("shutdown metric exporter %q: %v", kind, err)
		}
	}
	_, err := otelsdk.DefaultSpanExporterFactory(context.Background(), "unknown", settings)
	assertProblemID(t, err, otel.FaultConfigInvalid)
	_, err = otelsdk.DefaultMetricExporterFactory(context.Background(), "unknown", settings)
	assertProblemID(t, err, otel.FaultConfigInvalid)
}

func TestDefaultOtlpFactoriesRejectInvalidURLs(t *testing.T) {
	t.Parallel()

	invalid := "://"
	settings := otel.OtlpSettings{URL: &invalid}
	if _, err := otelsdk.DefaultSpanExporterFactory(context.Background(), otelsdk.ExporterOtlp, settings); err == nil {
		t.Fatal("invalid span exporter URL accepted")
	}
	if _, err := otelsdk.DefaultMetricExporterFactory(context.Background(), otelsdk.ExporterOtlp, settings); err == nil {
		t.Fatal("invalid metric exporter URL accepted")
	}
}
