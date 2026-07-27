// Package metrics registers and records the fleet-operator's metrics alongside
// the controller-runtime reconcile metrics. The generic foundation is a
// condition-state gauge, a durable-ledger failure counter, and a reconcile
// liveness counter; the fleet taxonomy extends it additively with vendor/DNS
// API failures, provisioning durations, a last-successful-tick TIMESTAMP gauge
// (staleness = time() - value, never a tick rate), webhook config-compile and
// tenant-sync failures, per-landscape materialization/ack lag, and the
// observe-mode would-apply plan-action surface. The chart alert pack, dashboard,
// and metric-taxonomy ConfigMap reference only the names registered here.
//
// Every public label value is BOUNDED at this recorder boundary: controller,
// vendor, and condition type are folded to a closed documented vocabulary plus
// the fixed LabelOther sentinel, so a caller cannot create a new time series
// from an arbitrary, object-derived, or secret-bearing string. The vocabularies
// are mirrored by the chart (infra/root_chart/values.yaml metricLabels and the
// metric-taxonomy ConfigMap) and cross-checked by
// scripts/validate/operator-observability-artifacts.ts.
package metrics

import (
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	crmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
)

// Metric names (also referenced by the chart dashboard, alert group, and the
// metric-taxonomy ConfigMap). The first three are the byte-stable generic
// foundation; the rest are the additive fleet taxonomy.
const (
	ConditionMetric     = "fleet_operator_condition"
	LedgerFailureMetric = "fleet_operator_ledger_failures_total"
	ReconcileTickMetric = "fleet_operator_reconcile_ticks_total"

	VendorAPIFailureMetric      = "fleet_operator_vendor_api_failures_total"
	ProvisioningDurationMetric  = "fleet_operator_provisioning_duration_seconds"
	LastSuccessfulTickMetric    = "fleet_operator_last_successful_tick_timestamp_seconds"
	WebhookCompileFailureMetric = "fleet_operator_webhook_compile_failures_total"
	MaterializationAckLagMetric = "fleet_operator_materialization_ack_lag_seconds"
	TenantSyncFailureMetric     = "fleet_operator_tenant_sync_failures_total"
	PlanActionsMetric           = "fleet_operator_plan_actions"
)

// LabelOther is the single fixed overflow sentinel every bounded label folds
// unknown values into. It is deliberately one value for every vocabulary: an
// unbounded caller string can therefore add at most one child series per family,
// never one per distinct input, and is never exposed verbatim. The exact rejected
// value stays recoverable from the structured logs and the CR status, which are
// the per-object surfaces; metrics are the bounded alertable aggregate.
const LabelOther = "other"

// controllerVocabulary is the closed controller label vocabulary: every real
// enable seam the runtime declares, including the reserved
// "problem" seam — a known future controller must land on its own label rather
// than collapse into LabelOther the day its writer arrives. It is mirrored by
// infra/root_chart/values.yaml metricLabels.controllers, which the alert pack
// validates its own controller= selectors against — a selector naming a value
// outside this set could never match a series.
//
// BEGIN taxonomy:controllers — the validator parses the literals between these markers.
var controllerVocabulary = []string{
	"cluster",
	"platform",
	"dependency",
	"traffic",
	"webhook",
	"cf-deploy",
	// Reserved: the runtime declares an --enable-problem seam that is not folded
	// yet (ErrProblemNotFolded), so nothing emits under this label today.
	"problem",
}

// END taxonomy:controllers.

// vendorVocabulary is the closed vendor label vocabulary for the vendor/DNS API
// failure counter. The ProviderAccount CRD's vendor grammar is deliberately open
// (docs/domain/provider-accounts.md), so this observability vocabulary is NOT
// that grammar: an unlisted vendor is recorded as LabelOther and identified from
// the vendor-call-failure log line instead of by minting a new series.
//
// BEGIN taxonomy:vendors — the validator parses the literals between these markers.
var vendorVocabulary = []string{
	"cloudflare",
	"neon",
	"aws",
	"infisical",
	"mercury",
}

// END taxonomy:vendors.

// conditionTypeVocabulary consumes the pure condition constants from
// lib/operator/conditions rather than duplicating their spelling, so the metric
// label vocabulary and the condition vocabulary controllers actually flip cannot
// drift apart. An unlisted type folds into LabelOther: the exact per-type state
// is always readable from the CR status, and every paging type below is bounded.
var conditionTypeVocabulary = []string{
	conditions.TypeReady,
	conditions.TypeDrifted,
	conditions.TypeConflict,
	conditions.TypeWaitingForEndpoint,
	conditions.TypeBlastBrakeTripped,

	conditions.TypeProvisioned,
	conditions.TypeSecretWritten,
	conditions.TypeUnresolved,
	conditions.TypeNotInEnvelope,
	conditions.TypeSecretRetained,
	conditions.TypeDeclarerChanged,
	conditions.TypeForkUnsupported,
	conditions.TypeQuotaExhausted,

	conditions.TypeInfisicalProvisioned,
	conditions.TypeSoSRegistered,
	conditions.TypePipelineRendered,
	conditions.TypeOrphanedSource,

	conditions.TypeConfigCompiled,
	conditions.TypeSecretsFanned,
	conditions.TypeHomeChangeBlocked,
	conditions.TypeTargetNotServed,
	conditions.TypeAccepted,
	conditions.TypeUnknownProvider,
	conditions.TypeOrphanedProvider,
	conditions.TypeTenantProvisioned,

	conditions.TypeRefsClear,
	conditions.TypeSnapshotted,
	conditions.TypeExternalsDeleted,
	conditions.TypeLedgerPurged,
	conditions.TypeTargetDeleted,

	conditions.TypeRecordPublished,
	conditions.TypeNoActiveServers,

	conditions.TypeVersionFound,
	conditions.TypeRolloutProgressing,
	conditions.TypeRolloutComplete,
	conditions.TypeDriftDetected,
	conditions.TypeFailed,

	conditions.TypePublished,
	conditions.TypeSchemaInvalid,
	conditions.TypeStale,
}

var (
	controllerAllowed    = index(controllerVocabulary)
	vendorAllowed        = index(vendorVocabulary)
	conditionTypeAllowed = index(conditionTypeVocabulary)
)

// index builds the membership set for a vocabulary.
func index(values []string) map[string]struct{} {
	set := make(map[string]struct{}, len(values))
	for _, v := range values {
		set[v] = struct{}{}
	}
	return set
}

// copyOf returns a defensive copy so an exported vocabulary cannot be mutated by
// a caller (or a test) into a wider label surface than the recorder enforces.
func copyOf(values []string) []string {
	return append([]string(nil), values...)
}

// Controllers returns the bounded controller label vocabulary (LabelOther aside).
func Controllers() []string { return copyOf(controllerVocabulary) }

// Vendors returns the bounded vendor label vocabulary (LabelOther aside).
func Vendors() []string { return copyOf(vendorVocabulary) }

// ConditionTypes returns the bounded condition-type label vocabulary
// (LabelOther aside), derived from the pure lib/operator/conditions constants.
func ConditionTypes() []string { return copyOf(conditionTypeVocabulary) }

// bound folds a caller-supplied label value to its vocabulary, or to LabelOther.
func bound(allowed map[string]struct{}, value string) string {
	if _, ok := allowed[value]; ok {
		return value
	}
	return LabelOther
}

// BoundController folds a controller name to the bounded controller label value
// the recorder would use. It exists so a caller (or a test) can predict the
// recorded series without re-deriving the vocabulary.
func BoundController(controller string) string { return bound(controllerAllowed, controller) }

// BoundVendor folds a vendor name to the bounded vendor label value.
func BoundVendor(vendor string) string { return bound(vendorAllowed, vendor) }

// BoundConditionType folds a condition type to the bounded type label value.
func BoundConditionType(conditionType string) string {
	return bound(conditionTypeAllowed, conditionType)
}

// Recorder is the metrics port controllers use. The generic methods stay
// byte-compatible; the fleet taxonomy is additive. Every string argument is a
// caller-convenient name, NOT a raw label: the implementation folds it to the
// bounded vocabulary above, so passing an object-derived or secret-bearing value
// can only ever land on LabelOther.
type Recorder interface {
	// Observe sets the condition-state gauge (1 for True, else 0) for each condition.
	Observe(controller string, states []metav1.Condition)
	// LedgerFailure increments the durable-ledger failure counter.
	LedgerFailure(controller string)
	// Tick increments the reconcile liveness counter.
	Tick(controller string)

	// VendorAPIFailure increments the vendor/DNS API failure counter for a controller and vendor.
	VendorAPIFailure(controller, vendor string)
	// ObserveProvisioning records an external-resource provisioning duration sample (seconds).
	ObserveProvisioning(controller string, seconds float64)
	// MarkTick stamps the controller's last successful reconcile/poll tick as a Unix
	// TIMESTAMP (seconds). Liveness is staleness — time() - value — never a tick rate,
	// so a frozen poll loop is loudly known instead of averaging away. Only a
	// controller configured in the chart's alerts.tickProducerControllers gets a
	// staleness alert, so a controller with no writer never pages on an empty series.
	MarkTick(controller string, at time.Time)
	// WebhookCompileFailure increments the webhook config-compile failure counter.
	WebhookCompileFailure(controller string)
	// ObserveMaterializationAckLag sets the current per-landscape materialization/ack lag (seconds).
	ObserveMaterializationAckLag(controller string, seconds float64)
	// TenantSyncFailure increments the webhook tenant-sync failure counter.
	TenantSyncFailure(controller string)
	// SetPlanActions sets the observe-mode would-apply plan-action count for a controller,
	// split by whether the pending actions are destructive.
	SetPlanActions(controller string, destructive bool, count float64)
}

var (
	conditionGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: ConditionMetric,
		Help: "Operator condition state (1 True, 0 otherwise) by controller and type; both labels are bounded vocabularies with an 'other' overflow.",
	}, []string{"controller", "type"})

	ledgerFailures = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: LedgerFailureMetric,
		Help: "Durable-ledger operation failures by controller.",
	}, []string{"controller"})

	reconcileTicks = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: ReconcileTickMetric,
		Help: "Reconcile loop liveness ticks by controller.",
	}, []string{"controller"})

	vendorAPIFailures = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: VendorAPIFailureMetric,
		Help: "Vendor/DNS API call failures by controller and vendor; both labels are bounded vocabularies with an 'other' overflow.",
	}, []string{"controller", "vendor"})

	provisioningDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    ProvisioningDurationMetric,
		Help:    "External-resource provisioning durations in seconds by controller.",
		Buckets: prometheus.ExponentialBuckets(1, 2, 12),
	}, []string{"controller"})

	lastSuccessfulTick = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: LastSuccessfulTickMetric,
		Help: "Unix timestamp (seconds) of the last successful reconcile/poll tick by controller; staleness = time() - value.",
	}, []string{"controller"})

	webhookCompileFailures = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: WebhookCompileFailureMetric,
		Help: "Webhook config-compile failures by controller.",
	}, []string{"controller"})

	materializationAckLag = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: MaterializationAckLagMetric,
		Help: "Current per-landscape materialization/ack lag in seconds by controller.",
	}, []string{"controller"})

	tenantSyncFailures = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: TenantSyncFailureMetric,
		Help: "Webhook internal-tenant sync failures by controller.",
	}, []string{"controller"})

	planActions = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: PlanActionsMetric,
		Help: "Observe-mode would-apply plan-action count by controller and destructive flag.",
	}, []string{"controller", "destructive"})

	_ = register()
)

func register() bool {
	crmetrics.Registry.MustRegister(
		conditionGauge,
		ledgerFailures,
		reconcileTicks,
		vendorAPIFailures,
		provisioningDuration,
		lastSuccessfulTick,
		webhookCompileFailures,
		materializationAckLag,
		tenantSyncFailures,
		planActions,
	)
	return true
}

// Prometheus is the production Recorder backed by the controller-runtime registry.
type Prometheus struct{}

var _ Recorder = Prometheus{}

// NewPrometheus constructs the Prometheus Recorder.
func NewPrometheus() Prometheus { return Prometheus{} }

// Observe sets the condition-state gauge for each condition. An unlisted
// condition type aggregates onto the 'other' child rather than minting a series.
func (Prometheus) Observe(controller string, states []metav1.Condition) {
	ctrl := bound(controllerAllowed, controller)
	for i := range states {
		value := 0.0
		if states[i].Status == metav1.ConditionTrue {
			value = 1.0
		}
		conditionGauge.WithLabelValues(ctrl, bound(conditionTypeAllowed, states[i].Type)).Set(value)
	}
}

// LedgerFailure increments the durable-ledger failure counter.
func (Prometheus) LedgerFailure(controller string) {
	ledgerFailures.WithLabelValues(bound(controllerAllowed, controller)).Inc()
}

// Tick increments the reconcile liveness counter.
func (Prometheus) Tick(controller string) {
	reconcileTicks.WithLabelValues(bound(controllerAllowed, controller)).Inc()
}

// VendorAPIFailure increments the vendor/DNS API failure counter.
func (Prometheus) VendorAPIFailure(controller, vendor string) {
	vendorAPIFailures.WithLabelValues(bound(controllerAllowed, controller), bound(vendorAllowed, vendor)).Inc()
}

// ObserveProvisioning records a provisioning duration sample in seconds.
func (Prometheus) ObserveProvisioning(controller string, seconds float64) {
	provisioningDuration.WithLabelValues(bound(controllerAllowed, controller)).Observe(seconds)
}

// MarkTick stamps the controller's last successful tick as a Unix timestamp (seconds).
func (Prometheus) MarkTick(controller string, at time.Time) {
	lastSuccessfulTick.WithLabelValues(bound(controllerAllowed, controller)).Set(float64(at.Unix()))
}

// WebhookCompileFailure increments the webhook config-compile failure counter.
func (Prometheus) WebhookCompileFailure(controller string) {
	webhookCompileFailures.WithLabelValues(bound(controllerAllowed, controller)).Inc()
}

// ObserveMaterializationAckLag sets the current materialization/ack lag in seconds.
func (Prometheus) ObserveMaterializationAckLag(controller string, seconds float64) {
	materializationAckLag.WithLabelValues(bound(controllerAllowed, controller)).Set(seconds)
}

// TenantSyncFailure increments the webhook tenant-sync failure counter.
func (Prometheus) TenantSyncFailure(controller string) {
	tenantSyncFailures.WithLabelValues(bound(controllerAllowed, controller)).Inc()
}

// SetPlanActions sets the observe-mode would-apply plan-action count for a controller,
// split by whether the pending actions are destructive.
func (Prometheus) SetPlanActions(controller string, destructive bool, count float64) {
	planActions.WithLabelValues(bound(controllerAllowed, controller), strconv.FormatBool(destructive)).Set(count)
}
