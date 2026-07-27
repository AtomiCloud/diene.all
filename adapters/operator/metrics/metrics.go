// Package metrics registers and records the fleet-operator's metrics alongside
// the controller-runtime reconcile metrics. The generic foundation is a
// condition-state gauge, a durable-ledger failure counter, and a reconcile
// liveness counter; the fleet taxonomy extends it additively with vendor/DNS
// API failures, provisioning durations, a last-successful-tick TIMESTAMP gauge
// (staleness = time() - value, never a tick rate), webhook config-compile and
// tenant-sync failures, per-landscape materialization/ack lag, and the
// observe-mode would-apply plan-action surface. The chart alert pack, dashboard,
// and metric-taxonomy ConfigMap reference only the names registered here.
package metrics

import (
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	crmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"
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

// Recorder is the metrics port controllers use. The generic methods stay
// byte-compatible; the fleet taxonomy is additive.
type Recorder interface {
	// Observe sets the condition-state gauge (1 for True, else 0) for each condition.
	Observe(controller string, conditions []metav1.Condition)
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
	// so a frozen poll loop is loudly known instead of averaging away.
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
		Help: "Operator condition state (1 True, 0 otherwise) by controller and type.",
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
		Help: "Vendor/DNS API call failures by controller and vendor.",
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

// Observe sets the condition-state gauge for each condition.
func (Prometheus) Observe(controller string, conditions []metav1.Condition) {
	for i := range conditions {
		value := 0.0
		if conditions[i].Status == metav1.ConditionTrue {
			value = 1.0
		}
		conditionGauge.WithLabelValues(controller, conditions[i].Type).Set(value)
	}
}

// LedgerFailure increments the durable-ledger failure counter.
func (Prometheus) LedgerFailure(controller string) {
	ledgerFailures.WithLabelValues(controller).Inc()
}

// Tick increments the reconcile liveness counter.
func (Prometheus) Tick(controller string) {
	reconcileTicks.WithLabelValues(controller).Inc()
}

// VendorAPIFailure increments the vendor/DNS API failure counter.
func (Prometheus) VendorAPIFailure(controller, vendor string) {
	vendorAPIFailures.WithLabelValues(controller, vendor).Inc()
}

// ObserveProvisioning records a provisioning duration sample in seconds.
func (Prometheus) ObserveProvisioning(controller string, seconds float64) {
	provisioningDuration.WithLabelValues(controller).Observe(seconds)
}

// MarkTick stamps the controller's last successful tick as a Unix timestamp (seconds).
func (Prometheus) MarkTick(controller string, at time.Time) {
	lastSuccessfulTick.WithLabelValues(controller).Set(float64(at.Unix()))
}

// WebhookCompileFailure increments the webhook config-compile failure counter.
func (Prometheus) WebhookCompileFailure(controller string) {
	webhookCompileFailures.WithLabelValues(controller).Inc()
}

// ObserveMaterializationAckLag sets the current materialization/ack lag in seconds.
func (Prometheus) ObserveMaterializationAckLag(controller string, seconds float64) {
	materializationAckLag.WithLabelValues(controller).Set(seconds)
}

// TenantSyncFailure increments the webhook tenant-sync failure counter.
func (Prometheus) TenantSyncFailure(controller string) {
	tenantSyncFailures.WithLabelValues(controller).Inc()
}

// SetPlanActions sets the observe-mode would-apply plan-action count for a controller,
// split by whether the pending actions are destructive.
func (Prometheus) SetPlanActions(controller string, destructive bool, count float64) {
	planActions.WithLabelValues(controller, strconv.FormatBool(destructive)).Set(count)
}
