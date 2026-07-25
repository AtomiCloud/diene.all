// Package metrics registers and records Boron generic metrics
// alongside the controller-runtime reconcile metrics: a condition-state gauge, a
// provider failure counter, and a reconcile liveness counter. Consumers
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
	ConditionMetric     = "boron_condition"
	ProviderFailureMetric = "boron_provider_failures_total"
	ReconcileTickMetric = "boron_reconcile_ticks_total"
)

// Recorder is the metrics port controllers use.
type Recorder interface {
	// Observe sets the condition-state gauge (1 for True, else 0) for each condition.
	Observe(controller string, conditions []metav1.Condition)
	// ProviderFailure increments the provider failure counter.
	ProviderFailure(controller string)
	// Tick increments the reconcile liveness counter.
	Tick(controller string)
}

var (
	conditionGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: ConditionMetric,
		Help: "Operator condition state (1 True, 0 otherwise) by controller and type.",
	}, []string{"controller", "type"})

	providerFailures = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: ProviderFailureMetric,
		Help: "Provider operation failures by controller.",
	}, []string{"controller"})

	reconcileTicks = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: ReconcileTickMetric,
		Help: "Reconcile loop liveness ticks by controller.",
	}, []string{"controller"})

	_ = register()
)

func register() bool {
	crmetrics.Registry.MustRegister(conditionGauge, providerFailures, reconcileTicks)
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

// ProviderFailure increments the provider failure counter.
func (Prometheus) ProviderFailure(controller string) {
	providerFailures.WithLabelValues(controller).Inc()
}

// Tick increments the reconcile liveness counter.
func (Prometheus) Tick(controller string) {
	reconcileTicks.WithLabelValues(controller).Inc()
}
