// Package metrics registers and records the operator template's generic metrics
// alongside the controller-runtime reconcile metrics: a condition-state gauge, a
// durable-ledger failure counter, and a reconcile liveness counter. Consumers
// extend the same names for their provisioning/vendor/webhook taxonomy (shipped
// as parameterized dashboard and alert source in the chart).
package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	crmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"
)

// Metric names (also referenced by the chart dashboard and alert group).
const (
	ConditionMetric     = "fleet_operator_condition"
	LedgerFailureMetric = "fleet_operator_ledger_failures_total"
	ReconcileTickMetric = "fleet_operator_reconcile_ticks_total"
)

// Recorder is the metrics port controllers use.
type Recorder interface {
	// Observe sets the condition-state gauge (1 for True, else 0) for each condition.
	Observe(controller string, conditions []metav1.Condition)
	// LedgerFailure increments the durable-ledger failure counter.
	LedgerFailure(controller string)
	// Tick increments the reconcile liveness counter.
	Tick(controller string)
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

	_ = register()
)

func register() bool {
	crmetrics.Registry.MustRegister(conditionGauge, ledgerFailures, reconcileTicks)
	return true
}

// Prometheus is the production Recorder backed by the controller-runtime registry.
type Prometheus struct{}

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
