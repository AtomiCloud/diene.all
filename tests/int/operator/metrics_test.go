package operator_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	crmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/metrics"
)

// What these tests prove, and what they deliberately do not.
//
// PROVEN: the metric families the chart's alert pack, dashboard, and taxonomy
// reference are really exposed over HTTP, in Prometheus text exposition, by the
// same promhttp handler over the same controller-runtime registry the manager's
// metrics server serves (sigs.k8s.io/controller-runtime/pkg/metrics/server builds
// exactly promhttp.HandlerFor(metrics.Registry, HandlerOpts{ErrorHandling:
// HTTPErrorOnError})); their exact label-name/value sets, their Prometheus types,
// their values; that a later tick advances the liveness TIMESTAMP; that unknown
// controller/vendor/condition values aggregate onto the single `other` sentinel
// instead of minting series or appearing verbatim; and that no retired webhook
// delivery-path family or state label is exposed.
//
// NOT PROVEN HERE: the authn/authz filter (the manager wraps the same handler with
// controller-runtime's filter and the chart ships the scraper identity and RBAC —
// asserted by scripts/validate/operator-observability-artifacts.ts, not by this
// test, which scrapes an unfiltered httptest handler), and production call sites.
// In Phase 2 the fleet taxonomy has no real reconciler writers yet: the Phase 3
// controllers are the ones that will call MarkTick and the vendor/provisioning
// recorders, and the fenced sample controllers deliberately do not. These tests
// therefore prove the exposition contract of the recorder, not that a real
// reconcile drives it. That is also why the timestamp-staleness alert is rendered
// only for controllers explicitly declared as tick producers in the chart.

// exposed is a parsed Prometheus text-exposition response.
type exposed struct {
	types  map[string]string
	series []exposedSeries
	body   string
}

// exposedSeries is one exposition line: a metric name, its complete label set, and
// its value. The label set is complete on purpose — an unexpected extra label must
// fail an assertion instead of being ignored.
type exposedSeries struct {
	name   string
	labels map[string]string
	value  float64
}

// splitLabelPairs splits a label block on commas that are not inside a quoted
// value, so a label value containing a comma cannot corrupt the parse.
func splitLabelPairs(block string) []string {
	var pairs []string
	var current strings.Builder
	inQuote := false
	escaped := false
	for _, r := range block {
		switch {
		case escaped:
			escaped = false
			current.WriteRune(r)
		case r == '\\' && inQuote:
			escaped = true
			current.WriteRune(r)
		case r == '"':
			inQuote = !inQuote
			current.WriteRune(r)
		case r == ',' && !inQuote:
			pairs = append(pairs, current.String())
			current.Reset()
		default:
			current.WriteRune(r)
		}
	}
	if strings.TrimSpace(current.String()) != "" {
		pairs = append(pairs, current.String())
	}
	return pairs
}

// parseExposition parses Prometheus text exposition (# TYPE lines plus samples).
func parseExposition(t *testing.T, body string) exposed {
	t.Helper()
	out := exposed{types: map[string]string{}, body: body}
	for raw := range strings.SplitSeq(body, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "#") {
			fields := strings.Fields(line)
			if len(fields) == 4 && fields[1] == "TYPE" {
				out.types[fields[2]] = fields[3]
			}
			continue
		}

		var name, rest string
		labels := map[string]string{}
		if open := strings.Index(line, "{"); open >= 0 {
			closeAt := strings.LastIndex(line, "}")
			require.Greaterf(t, closeAt, open, "malformed exposition line %q", line)
			name = line[:open]
			for _, pair := range splitLabelPairs(line[open+1 : closeAt]) {
				key, quoted, ok := strings.Cut(strings.TrimSpace(pair), "=")
				require.Truef(t, ok, "malformed label pair %q", pair)
				value, uerr := strconv.Unquote(quoted)
				require.NoErrorf(t, uerr, "unquoting label value %q", quoted)
				labels[strings.TrimSpace(key)] = value
			}
			rest = line[closeAt+1:]
		} else {
			cut := strings.Index(line, " ")
			require.Greaterf(t, cut, 0, "malformed exposition line %q", line)
			name = line[:cut]
			rest = line[cut:]
		}

		fields := strings.Fields(rest)
		require.NotEmptyf(t, fields, "exposition line for %q carries no value", name)
		value, perr := strconv.ParseFloat(fields[0], 64)
		require.NoErrorf(t, perr, "parsing value of %q", name)
		out.series = append(out.series, exposedSeries{name: name, labels: labels, value: value})
	}
	return out
}

// matching returns every scraped series with exactly the given complete label set.
func (e exposed) matching(name string, labels map[string]string) []exposedSeries {
	var found []exposedSeries
	for _, s := range e.series {
		if s.name != name || len(s.labels) != len(labels) {
			continue
		}
		match := true
		for k, v := range labels {
			if s.labels[k] != v {
				match = false
				break
			}
		}
		if match {
			found = append(found, s)
		}
	}
	return found
}

// only returns the single series carrying exactly the given complete label set,
// failing if it is missing or duplicated.
func (e exposed) only(t *testing.T, name string, labels map[string]string) exposedSeries {
	t.Helper()
	found := e.matching(name, labels)
	require.Lenf(t, found, 1, "expected exactly one %s series with exact labels %v", name, labels)
	return found[0]
}

// absent asserts no series with exactly the given complete label set exists.
func (e exposed) absent(t *testing.T, name string, labels map[string]string) {
	t.Helper()
	require.Emptyf(t, e.matching(name, labels), "unexpected %s series with labels %v", name, labels)
}

// value returns the current value of an exact series, or 0 when it has no child
// yet — a not-yet-created counter child is indistinguishable from zero to a
// scraper, which is exactly the baseline a delta assertion needs.
func (e exposed) value(name string, labels map[string]string) float64 {
	found := e.matching(name, labels)
	if len(found) == 0 {
		return 0
	}
	return found[0].value
}

// controllerLabels of a family whose only label is controller.
func (e exposed) controllerSeries(name string) []exposedSeries {
	var found []exposedSeries
	for _, s := range e.series {
		if s.name == name {
			found = append(found, s)
		}
	}
	return found
}

// scrapeRegistry serves the controller-runtime registry through the same promhttp
// handler construction the manager's metrics server uses, over real HTTP, and
// returns the parsed text exposition. This is the round-trip, not a Gather() call.
func scrapeRegistry(t *testing.T) exposed {
	t.Helper()
	server := httptest.NewServer(promhttp.HandlerFor(crmetrics.Registry, promhttp.HandlerOpts{
		ErrorHandling: promhttp.HTTPErrorOnError,
	}))
	defer server.Close()

	resp, err := http.Get(server.URL + "/metrics") //nolint:noctx // httptest server, no cancellation surface needed
	require.NoError(t, err)
	defer func() { require.NoError(t, resp.Body.Close()) }()

	require.Equal(t, http.StatusOK, resp.StatusCode)
	require.Contains(t, resp.Header.Get("Content-Type"), "text/plain")
	raw, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	require.NotEmpty(t, raw)
	return parseExposition(t, string(raw))
}

// TestMetricsHTTPExpositionFamilies proves every generic and fleet-taxonomy family
// the chart references is exposed over HTTP with the expected Prometheus type and
// the exact label set the chart's alert/dashboard expressions group by. A
// label-less vec is omitted from a scrape until it has a child, so one bounded
// probe controller records a sample per family first.
func TestMetricsHTTPExpositionFamilies(t *testing.T) {
	rec := metrics.NewPrometheus()
	const probe = "cf-deploy"
	rec.Observe(probe, []metav1.Condition{{Type: "Ready", Status: metav1.ConditionTrue}})
	rec.LedgerFailure(probe)
	rec.Tick(probe)
	rec.VendorAPIFailure(probe, "cloudflare")
	rec.ObserveProvisioning(probe, 1)
	rec.MarkTick(probe, time.Unix(1, 0))
	rec.WebhookCompileFailure(probe)
	rec.ObserveMaterializationAckLag(probe, 1)
	rec.TenantSyncFailure(probe)
	rec.SetPlanActions(probe, true, 1)

	scrape := scrapeRegistry(t)

	wantType := map[string]string{
		metrics.ConditionMetric:             "gauge",
		metrics.LedgerFailureMetric:         "counter",
		metrics.ReconcileTickMetric:         "counter",
		metrics.VendorAPIFailureMetric:      "counter",
		metrics.ProvisioningDurationMetric:  "histogram",
		metrics.LastSuccessfulTickMetric:    "gauge",
		metrics.WebhookCompileFailureMetric: "counter",
		metrics.MaterializationAckLagMetric: "gauge",
		metrics.TenantSyncFailureMetric:     "counter",
		metrics.PlanActionsMetric:           "gauge",
	}
	for name, typ := range wantType {
		require.Equalf(t, typ, scrape.types[name], "exposed type of family %s", name)
	}

	// Exact, complete label sets — an unexpected extra label fails here.
	scrape.only(t, metrics.ConditionMetric, map[string]string{"controller": probe, "type": "Ready"})
	scrape.only(t, metrics.LedgerFailureMetric, map[string]string{"controller": probe})
	scrape.only(t, metrics.ReconcileTickMetric, map[string]string{"controller": probe})
	scrape.only(t, metrics.VendorAPIFailureMetric, map[string]string{"controller": probe, "vendor": "cloudflare"})
	scrape.only(t, metrics.ProvisioningDurationMetric+"_count", map[string]string{"controller": probe})
	scrape.only(t, metrics.LastSuccessfulTickMetric, map[string]string{"controller": probe})
	scrape.only(t, metrics.WebhookCompileFailureMetric, map[string]string{"controller": probe})
	scrape.only(t, metrics.MaterializationAckLagMetric, map[string]string{"controller": probe})
	scrape.only(t, metrics.TenantSyncFailureMetric, map[string]string{"controller": probe})
	scrape.only(t, metrics.PlanActionsMetric, map[string]string{"controller": probe, "destructive": "true"})

	// This is the real controller-runtime registry, not a hand-built subset: the
	// process collectors it always registers are in the same response. The
	// controller_runtime_reconcile_* families the chart's RED panels query are
	// framework-owned vecs that only appear once a controller has reconciled, so
	// their exposition is not asserted from this recorder-focused test.
	require.Contains(t, scrape.types, "process_start_time_seconds")
	require.Contains(t, scrape.types, "go_goroutines")
}

// TestMetricsHTTPExpositionValuesAndTimestamp asserts the recorded values of the
// fleet taxonomy as scraped, and the timestamp-staleness semantics of the liveness
// gauge: it is a Unix TIMESTAMP that advances on a later tick, never a tick rate.
// Deltas are taken against a baseline scrape so the assertions hold regardless of
// what any other test in this package recorded.
func TestMetricsHTTPExpositionValuesAndTimestamp(t *testing.T) {
	rec := metrics.NewPrometheus()
	const ctrl = "platform"
	vendorLabels := map[string]string{"controller": ctrl, "vendor": "neon"}
	before := scrapeRegistry(t)
	baseVendor := before.value(metrics.VendorAPIFailureMetric, vendorLabels)
	baseCompile := before.value(metrics.WebhookCompileFailureMetric, map[string]string{"controller": ctrl})
	baseTenant := before.value(metrics.TenantSyncFailureMetric, map[string]string{"controller": ctrl})
	baseProvisioning := before.value(metrics.ProvisioningDurationMetric+"_count", map[string]string{"controller": ctrl})
	baseProvisioningSum := before.value(metrics.ProvisioningDurationMetric+"_sum", map[string]string{"controller": ctrl})

	rec.VendorAPIFailure(ctrl, "neon")
	rec.VendorAPIFailure(ctrl, "neon")
	rec.ObserveProvisioning(ctrl, 12.5)
	rec.WebhookCompileFailure(ctrl)
	rec.TenantSyncFailure(ctrl)
	rec.ObserveMaterializationAckLag(ctrl, 42)
	rec.SetPlanActions(ctrl, true, 3)
	rec.SetPlanActions(ctrl, false, 7)

	first := time.Unix(1_700_000_000, 0)
	rec.MarkTick(ctrl, first)

	scrape := scrapeRegistry(t)

	require.Equal(t, baseVendor+2, scrape.only(t, metrics.VendorAPIFailureMetric, vendorLabels).value)
	require.Equal(t, baseCompile+1,
		scrape.only(t, metrics.WebhookCompileFailureMetric, map[string]string{"controller": ctrl}).value)
	require.Equal(t, baseTenant+1,
		scrape.only(t, metrics.TenantSyncFailureMetric, map[string]string{"controller": ctrl}).value)
	require.Equal(t, baseProvisioning+1,
		scrape.only(t, metrics.ProvisioningDurationMetric+"_count", map[string]string{"controller": ctrl}).value)
	require.InDelta(t, baseProvisioningSum+12.5,
		scrape.only(t, metrics.ProvisioningDurationMetric+"_sum", map[string]string{"controller": ctrl}).value, 1e-9)
	require.Equal(t, 42.0,
		scrape.only(t, metrics.MaterializationAckLagMetric, map[string]string{"controller": ctrl}).value)
	require.Equal(t, 3.0,
		scrape.only(t, metrics.PlanActionsMetric, map[string]string{"controller": ctrl, "destructive": "true"}).value)
	require.Equal(t, 7.0,
		scrape.only(t, metrics.PlanActionsMetric, map[string]string{"controller": ctrl, "destructive": "false"}).value)

	// The liveness gauge is the exact Unix second, and a later tick advances it.
	tickLabels := map[string]string{"controller": ctrl}
	require.Equal(t, float64(first.Unix()), scrape.only(t, metrics.LastSuccessfulTickMetric, tickLabels).value)
	later := first.Add(90 * time.Second)
	rec.MarkTick(ctrl, later)
	advanced := scrapeRegistry(t)
	require.Equal(t, float64(later.Unix()), advanced.only(t, metrics.LastSuccessfulTickMetric, tickLabels).value)
	require.Greater(t,
		advanced.only(t, metrics.LastSuccessfulTickMetric, tickLabels).value,
		scrape.only(t, metrics.LastSuccessfulTickMetric, tickLabels).value)
	// Staleness is derived from the exposed timestamp, not from a counter rate.
	require.Equal(t, "gauge", advanced.types[metrics.LastSuccessfulTickMetric])
	require.NotContains(t, metrics.LastSuccessfulTickMetric, "_total")
}

// TestMetricsBoundedLabelsAggregateUnknownToOther is the negative proof for the
// bounded-cardinality claim: arbitrary, object-derived, and secret-like strings
// never reach the exposition verbatim, and many distinct unknown values collapse
// onto the single `other` sentinel instead of minting one series each.
func TestMetricsBoundedLabelsAggregateUnknownToOther(t *testing.T) {
	rec := metrics.NewPrometheus()

	// Secret-like and object-derived strings a careless Phase 3 call site could pass.
	// The first is deliberately shaped like a leaked access-key id: the whole point
	// of this test is that such a value can never reach the exposition.
	const (
		secretish    = "AKIAIOSFODNN7EXAMPLE" //nolint:gosec // intentional secret-shaped input, not a credential
		objectish    = "cluster/default/my-obj-9f2c1b"
		injectionish = `evil",controller="cluster`
	)

	// A KNOWN controller with several UNKNOWN vendors must fold to exactly one
	// {controller, vendor=other} series carrying the sum, not one series per vendor.
	const ctrl = "traffic"
	otherVendor := map[string]string{"controller": ctrl, "vendor": metrics.LabelOther}
	baseOther := scrapeRegistry(t).value(metrics.VendorAPIFailureMetric, otherVendor)
	rec.VendorAPIFailure(ctrl, secretish)
	rec.VendorAPIFailure(ctrl, objectish)
	rec.VendorAPIFailure(ctrl, injectionish)
	rec.VendorAPIFailure(ctrl, "")

	// An UNKNOWN controller folds the same way.
	rec.Tick(objectish)
	rec.LedgerFailure(secretish)
	rec.ObserveMaterializationAckLag(injectionish, 5)

	// An UNKNOWN condition type folds; a known one on the same controller does not.
	rec.Observe(ctrl, []metav1.Condition{
		{Type: "Ready", Status: metav1.ConditionTrue},
		{Type: secretish, Status: metav1.ConditionTrue},
		{Type: objectish, Status: metav1.ConditionTrue},
	})

	scrape := scrapeRegistry(t)

	require.Equal(t, baseOther+4, scrape.only(t, metrics.VendorAPIFailureMetric, otherVendor).value,
		"four unknown vendors must sum onto one other series")
	for _, vendor := range []string{secretish, objectish, injectionish, ""} {
		scrape.absent(t, metrics.VendorAPIFailureMetric, map[string]string{"controller": ctrl, "vendor": vendor})
	}

	scrape.only(t, metrics.ReconcileTickMetric, map[string]string{"controller": metrics.LabelOther})
	scrape.only(t, metrics.LedgerFailureMetric, map[string]string{"controller": metrics.LabelOther})
	scrape.only(t, metrics.MaterializationAckLagMetric, map[string]string{"controller": metrics.LabelOther})
	scrape.absent(t, metrics.ReconcileTickMetric, map[string]string{"controller": objectish})
	scrape.absent(t, metrics.LedgerFailureMetric, map[string]string{"controller": secretish})

	require.Equal(t, 1.0, scrape.only(t, metrics.ConditionMetric,
		map[string]string{"controller": ctrl, "type": "Ready"}).value)
	scrape.only(t, metrics.ConditionMetric, map[string]string{"controller": ctrl, "type": metrics.LabelOther})
	scrape.absent(t, metrics.ConditionMetric, map[string]string{"controller": ctrl, "type": secretish})
	scrape.absent(t, metrics.ConditionMetric, map[string]string{"controller": ctrl, "type": objectish})

	// Zero exposure: not one of those strings appears anywhere in the response,
	// including inside a comment, a help text, or an escaped label value.
	for _, raw := range []string{secretish, objectish, "evil"} {
		require.NotContainsf(t, scrape.body, raw, "the exposition must never carry %q verbatim", raw)
	}

	// Every value the recorder folds is either a documented vocabulary member or
	// exactly the sentinel — the vocabularies themselves round-trip unchanged.
	for _, c := range metrics.Controllers() {
		require.Equal(t, c, metrics.BoundController(c))
	}
	for _, v := range metrics.Vendors() {
		require.Equal(t, v, metrics.BoundVendor(v))
	}
	for _, ct := range metrics.ConditionTypes() {
		require.Equal(t, ct, metrics.BoundConditionType(ct))
	}
	require.Equal(t, metrics.LabelOther, metrics.BoundController("nope"))
	require.Equal(t, metrics.LabelOther, metrics.BoundVendor("nope"))
	require.Equal(t, metrics.LabelOther, metrics.BoundConditionType("Nope"))
	require.Equal(t, "other", metrics.LabelOther)
	require.NotContains(t, metrics.Controllers(), metrics.LabelOther, "the sentinel is not a vocabulary member")
	require.NotContains(t, metrics.Vendors(), metrics.LabelOther, "the sentinel is not a vocabulary member")

	// The exported vocabulary is a copy: widening it from a caller is impossible.
	stolen := metrics.Controllers()
	stolen[0] = "hijacked"
	require.NotContains(t, metrics.Controllers(), "hijacked")
	require.Equal(t, metrics.LabelOther, metrics.BoundController("hijacked"))

	// Every scraped fleet series carries only bounded label values.
	allowedControllers := append(metrics.Controllers(), metrics.LabelOther)
	allowedVendors := append(metrics.Vendors(), metrics.LabelOther)
	allowedTypes := append(metrics.ConditionTypes(), metrics.LabelOther)
	for _, s := range scrape.series {
		if !strings.HasPrefix(s.name, "fleet_operator_") {
			continue
		}
		for label, value := range s.labels {
			switch label {
			case "controller":
				require.Containsf(t, allowedControllers, value, "%s controller label", s.name)
			case "vendor":
				require.Containsf(t, allowedVendors, value, "%s vendor label", s.name)
			case "type":
				require.Containsf(t, allowedTypes, value, "%s type label", s.name)
			case "destructive":
				require.Containsf(t, []string{"true", "false"}, value, "%s destructive label", s.name)
			case "le", "quantile":
				// histogram bucket boundaries are bounded by the fixed bucket set
			default:
				require.Failf(t, "unbounded label", "family %s exposes unexpected label %q", s.name, label)
			}
		}
	}
}

// TestMetricsExposesNoRetiredWebhookSurface proves the retired webhook
// delivery-path taxonomy is gone from the runtime surface, not merely from the
// chart: mercury owns the delivery path and exports those signals itself.
func TestMetricsExposesNoRetiredWebhookSurface(t *testing.T) {
	rec := metrics.NewPrometheus()
	// Record the webhook controller's real config-plane signals first, so the
	// absence assertions below cannot pass merely because nothing was emitted.
	rec.WebhookCompileFailure("webhook")
	rec.ObserveMaterializationAckLag("webhook", 7)
	rec.TenantSyncFailure("webhook")

	scrape := scrapeRegistry(t)

	scrape.only(t, metrics.WebhookCompileFailureMetric, map[string]string{"controller": "webhook"})
	require.Equal(t, 7.0,
		scrape.only(t, metrics.MaterializationAckLagMetric, map[string]string{"controller": "webhook"}).value)
	scrape.only(t, metrics.TenantSyncFailureMetric, map[string]string{"controller": "webhook"})

	for _, retired := range []string{
		"fleet_operator_webhook_events_total",
		"webhook_events",
		"webhook_state",
		"double-own",
		"no-owner",
		"dead-letter",
		"misroute",
	} {
		require.NotContainsf(t, scrape.body, retired, "the exposition must not carry the retired token %q", retired)
	}
	for family := range scrape.types {
		require.NotContainsf(t, family, "webhook_events", "no webhook delivery-event family may be registered (%s)", family)
	}
	for _, s := range scrape.series {
		_, hasState := s.labels["webhook_state"]
		require.Falsef(t, hasState, "%s must not carry a webhook delivery-state label", s.name)
	}
}

// TestMetricsGenericFoundationByteCompatible proves the three inherited metrics
// still record under their existing names and shapes through a real scrape,
// including the BlastBrakeTripped paging condition the alert pack watches on the
// shared condition gauge, using a real bounded controller label.
func TestMetricsGenericFoundationByteCompatible(t *testing.T) {
	rec := metrics.NewPrometheus()
	const ctrl = "cluster"
	labels := map[string]string{"controller": ctrl}

	before := scrapeRegistry(t)
	baseTicks := before.value(metrics.ReconcileTickMetric, labels)
	baseLedger := before.value(metrics.LedgerFailureMetric, labels)

	rec.Tick(ctrl)
	rec.LedgerFailure(ctrl)
	rec.Observe(ctrl, []metav1.Condition{
		{Type: "BlastBrakeTripped", Status: metav1.ConditionTrue},
		{Type: "Drifted", Status: metav1.ConditionFalse},
	})

	scrape := scrapeRegistry(t)
	require.Equal(t, baseTicks+1, scrape.only(t, metrics.ReconcileTickMetric, labels).value)
	require.Equal(t, baseLedger+1, scrape.only(t, metrics.LedgerFailureMetric, labels).value)
	require.Equal(t, 1.0, scrape.only(t, metrics.ConditionMetric,
		map[string]string{"controller": ctrl, "type": "BlastBrakeTripped"}).value)
	require.Equal(t, 0.0, scrape.only(t, metrics.ConditionMetric,
		map[string]string{"controller": ctrl, "type": "Drifted"}).value)

	for _, controller := range []string{"cluster", "platform", "dependency", "traffic", "webhook", "cf-deploy", "problem"} {
		require.Contains(t, metrics.Controllers(), controller)
	}
	for _, retired := range []string{"n" + "ote", "jour" + "nal"} {
		require.NotContains(t, metrics.Controllers(), retired)
	}
	require.NotEmpty(t, scrape.controllerSeries(metrics.ReconcileTickMetric))
}
