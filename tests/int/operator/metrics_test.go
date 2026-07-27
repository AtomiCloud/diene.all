package operator_test

import (
	"testing"
	"time"

	dto "github.com/prometheus/client_model/go"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	crmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/metrics"
)

// gatherFamily returns the registered metric family scraped from the
// controller-runtime registry, or fails if the family is not registered.
func gatherFamily(t *testing.T, name string) *dto.MetricFamily {
	t.Helper()
	fams, err := crmetrics.Registry.Gather()
	require.NoError(t, err)
	for _, f := range fams {
		if f.GetName() == name {
			return f
		}
	}
	t.Fatalf("metric family %q is not registered", name)
	return nil
}

// metricFor returns the single sample carrying exactly the given label values.
func metricFor(t *testing.T, name string, labels map[string]string) *dto.Metric {
	t.Helper()
	f := gatherFamily(t, name)
	for _, m := range f.GetMetric() {
		got := make(map[string]string, len(m.GetLabel()))
		for _, lp := range m.GetLabel() {
			got[lp.GetName()] = lp.GetValue()
		}
		match := true
		for k, v := range labels {
			if got[k] != v {
				match = false
				break
			}
		}
		if match {
			return m
		}
	}
	t.Fatalf("metric %q with labels %v not found", name, labels)
	return nil
}

// TestMetricsFamiliesRegistered proves every generic and fleet-taxonomy family the
// chart references is registered by adapters/operator/metrics (so the chart can
// only reference emitted names), with the expected Prometheus type. A label-less
// vec is omitted from a scrape until it has a child, so a "probe" controller
// records one sample per family first — this is itself the scrape round-trip.
func TestMetricsFamiliesRegistered(t *testing.T) {
	rec := metrics.NewPrometheus()
	const probe = "metrics-probe-ctrl"
	rec.Observe(probe, []metav1.Condition{{Type: "Probe", Status: metav1.ConditionTrue}})
	rec.LedgerFailure(probe)
	rec.Tick(probe)
	rec.VendorAPIFailure(probe, "probe-vendor")
	rec.ObserveProvisioning(probe, 1)
	rec.MarkTick(probe, time.Unix(1, 0))
	rec.WebhookCompileFailure(probe)
	rec.ObserveMaterializationAckLag(probe, 1)
	rec.TenantSyncFailure(probe)
	rec.SetPlanActions(probe, true, 1)

	wantType := map[string]dto.MetricType{
		metrics.ConditionMetric:             dto.MetricType_GAUGE,
		metrics.LedgerFailureMetric:         dto.MetricType_COUNTER,
		metrics.ReconcileTickMetric:         dto.MetricType_COUNTER,
		metrics.VendorAPIFailureMetric:      dto.MetricType_COUNTER,
		metrics.ProvisioningDurationMetric:  dto.MetricType_HISTOGRAM,
		metrics.LastSuccessfulTickMetric:    dto.MetricType_GAUGE,
		metrics.WebhookCompileFailureMetric: dto.MetricType_COUNTER,
		metrics.MaterializationAckLagMetric: dto.MetricType_GAUGE,
		metrics.TenantSyncFailureMetric:     dto.MetricType_COUNTER,
		metrics.PlanActionsMetric:           dto.MetricType_GAUGE,
	}
	for name, typ := range wantType {
		require.Equalf(t, typ, gatherFamily(t, name).GetType(), "family %s type", name)
	}
}

// TestMetricsFleetTaxonomyRecords exercises every new Recorder adapter line and
// asserts the scraped label sets and values, plus the timestamp-staleness
// semantics of the liveness gauge. Unique controller/vendor labels keep the
// assertions independent of any other test that records generic metrics.
func TestMetricsFleetTaxonomyRecords(t *testing.T) {
	rec := metrics.NewPrometheus()

	// vendor/DNS API failures {controller,vendor}
	rec.VendorAPIFailure("metrics-vendor-ctrl", "neon")
	rec.VendorAPIFailure("metrics-vendor-ctrl", "neon")
	vm := metricFor(t, metrics.VendorAPIFailureMetric, map[string]string{"controller": "metrics-vendor-ctrl", "vendor": "neon"})
	require.Equal(t, 2.0, vm.GetCounter().GetValue())

	// provisioning duration histogram {controller}
	rec.ObserveProvisioning("metrics-prov-ctrl", 12.5)
	pm := metricFor(t, metrics.ProvisioningDurationMetric, map[string]string{"controller": "metrics-prov-ctrl"})
	require.Equal(t, uint64(1), pm.GetHistogram().GetSampleCount())
	require.InDelta(t, 12.5, pm.GetHistogram().GetSampleSum(), 1e-9)

	// last-successful-tick TIMESTAMP gauge {controller} — exact Unix seconds, and
	// a later tick advances the timestamp forward (staleness = time() - value).
	ts := time.Unix(1_700_000_000, 0)
	rec.MarkTick("metrics-tick-ctrl", ts)
	first := metricFor(t, metrics.LastSuccessfulTickMetric, map[string]string{"controller": "metrics-tick-ctrl"})
	require.Equal(t, float64(ts.Unix()), first.GetGauge().GetValue())
	later := ts.Add(90 * time.Second)
	rec.MarkTick("metrics-tick-ctrl", later)
	second := metricFor(t, metrics.LastSuccessfulTickMetric, map[string]string{"controller": "metrics-tick-ctrl"})
	require.Equal(t, float64(later.Unix()), second.GetGauge().GetValue())
	require.Greater(t, second.GetGauge().GetValue(), first.GetGauge().GetValue())

	// webhook config-compile failures {controller}
	rec.WebhookCompileFailure("metrics-webhook-ctrl")
	wm := metricFor(t, metrics.WebhookCompileFailureMetric, map[string]string{"controller": "metrics-webhook-ctrl"})
	require.Equal(t, 1.0, wm.GetCounter().GetValue())

	// materialization/ack lag gauge {controller}
	rec.ObserveMaterializationAckLag("metrics-acklag-ctrl", 42)
	am := metricFor(t, metrics.MaterializationAckLagMetric, map[string]string{"controller": "metrics-acklag-ctrl"})
	require.Equal(t, 42.0, am.GetGauge().GetValue())

	// tenant-sync failures {controller}
	rec.TenantSyncFailure("metrics-tenant-ctrl")
	sm := metricFor(t, metrics.TenantSyncFailureMetric, map[string]string{"controller": "metrics-tenant-ctrl"})
	require.Equal(t, 1.0, sm.GetCounter().GetValue())

	// observe-mode plan actions {controller,destructive}
	rec.SetPlanActions("metrics-plan-ctrl", true, 3)
	rec.SetPlanActions("metrics-plan-ctrl", false, 7)
	destructive := metricFor(t, metrics.PlanActionsMetric, map[string]string{"controller": "metrics-plan-ctrl", "destructive": "true"})
	require.Equal(t, 3.0, destructive.GetGauge().GetValue())
	safe := metricFor(t, metrics.PlanActionsMetric, map[string]string{"controller": "metrics-plan-ctrl", "destructive": "false"})
	require.Equal(t, 7.0, safe.GetGauge().GetValue())
}

// TestMetricsGenericFoundationByteCompatible proves the three inherited metrics
// still record under their existing names and shapes, including the BlastBrakeTripped
// paging condition the alert pack now watches on the shared condition gauge.
func TestMetricsGenericFoundationByteCompatible(t *testing.T) {
	rec := metrics.NewPrometheus()

	rec.Tick("metrics-generic-ctrl")
	require.Equal(t, 1.0,
		metricFor(t, metrics.ReconcileTickMetric, map[string]string{"controller": "metrics-generic-ctrl"}).GetCounter().GetValue())

	rec.LedgerFailure("metrics-generic-ctrl")
	require.Equal(t, 1.0,
		metricFor(t, metrics.LedgerFailureMetric, map[string]string{"controller": "metrics-generic-ctrl"}).GetCounter().GetValue())

	rec.Observe("metrics-generic-ctrl", []metav1.Condition{
		{Type: "BlastBrakeTripped", Status: metav1.ConditionTrue},
		{Type: "Drifted", Status: metav1.ConditionFalse},
	})
	require.Equal(t, 1.0,
		metricFor(t, metrics.ConditionMetric, map[string]string{"controller": "metrics-generic-ctrl", "type": "BlastBrakeTripped"}).GetGauge().GetValue())
	require.Equal(t, 0.0,
		metricFor(t, metrics.ConditionMetric, map[string]string{"controller": "metrics-generic-ctrl", "type": "Drifted"}).GetGauge().GetValue())
}
